#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

AWS_ACCOUNT=$(aws sts get-caller-identity | jq '.Account' -Mr)
if [[ $AWS_REGION == "" ]]; then
	AWS_REGION=$(aws configure get region)
fi
OIDC_S3_BUCKET_NAME=${1}

if [[ $OIDC_S3_BUCKET_NAME == "" ]]; then
	echo 1>&1 "OIDC bucket name parameter is mandatory."
	exit 1
fi

DNS_ZONE_NAME=${2}

if [[ $DNS_ZONE_NAME == "" ]]; then
	echo 1>&1 "DNS zone name not set"
	echo 1>&1 "DNS zone will not be managed"
fi

export AWS_ACCOUNT AWS_REGION OIDC_S3_BUCKET_NAME DNS_ZONE_NAME

policy_file=$(mktemp)
assume_policy_file=$(mktemp)

trap cleanup EXIT

function cleanup() {
	rm "$policy_file" 2>/dev/null
	rm "$assume_policy_file" 2>/dev/null
}

# create bucket for OIDC provider configuration
##################################################
echo "🚀 Creating S3 bucket for OIDC configuration..."
if aws s3api create-bucket --bucket "$OIDC_S3_BUCKET_NAME" --create-bucket-configuration="{\"LocationConstraint\":\"$AWS_REGION\"}" 2>/dev/null; then
	echo "✅ S3 bucket created: $OIDC_S3_BUCKET_NAME"
elif aws s3api head-bucket --bucket "$OIDC_S3_BUCKET_NAME" 2>/dev/null; then
	echo "✅ S3 bucket already exists: $OIDC_S3_BUCKET_NAME"
else
	echo "❌ Failed to create or access S3 bucket: $OIDC_S3_BUCKET_NAME"
	exit 1
fi

# Configure S3 bucket for public access
echo "🔧 Configuring S3 bucket for public access..."
aws s3api get-public-access-block --bucket "$OIDC_S3_BUCKET_NAME" &>/dev/null && \
  aws s3api delete-public-access-block --bucket "$OIDC_S3_BUCKET_NAME" || \
  echo "✅ No public access blocks to remove"

# Wait for cluster setup to complete before proceeding with OIDC provider configuration
# When this script is called by the Makefile setup-aws target, we're waiting for the actual OIDC files
# to be uploaded by setup-eks-webhook which happens later
# This is just placeholder configuration for now

# Function to properly configure OIDC discovery after files are uploaded
configure_oidc() {
  local bucket_name=$1
  local region=$2

  echo "🔧 Configuring OIDC discovery for AWS compatibility..."

  # Configure S3 bucket for public access
  echo "🔧 Ensuring S3 bucket allows public access..."
  aws s3api get-public-access-block --bucket "$bucket_name" &>/dev/null && \
    aws s3api delete-public-access-block --bucket "$bucket_name" || \
    echo "✅ No public access blocks to remove"

  # Set bucket policy to allow public read access to OIDC files
  echo "🔧 Setting bucket policy for OIDC access..."
  cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::${bucket_name}/cluster/acm-cluster/openid/v1/jwks",
        "arn:aws:s3:::${bucket_name}/cluster/acm-cluster/keys.json",
        "arn:aws:s3:::${bucket_name}/cluster/acm-cluster/.well-known/openid-configuration"
      ]
    }
  ]
}
EOF

  aws s3api put-bucket-policy --bucket "$bucket_name" --policy file:///tmp/bucket-policy.json || \
    { echo "❌ Failed to set bucket policy"; return 1; }

  # Create a copy of JWKS at standard path for AWS compatibility
  echo "🔧 Creating copy of JWKS at standard path for AWS compatibility..."
  if ! aws s3 cp "s3://$bucket_name/cluster/acm-cluster/openid/v1/jwks" "s3://$bucket_name/cluster/acm-cluster/keys.json"; then
    echo "❌ Failed to create keys.json copy - JWKS file might not exist yet"
    return 1
  fi

  # Update discovery document with required fields
  echo "🔧 Updating OIDC discovery document with required fields..."
  if ! aws s3 cp "s3://$bucket_name/cluster/acm-cluster/.well-known/openid-configuration" /tmp/openid-config.json; then
    echo "❌ Failed to download discovery document - it might not exist yet"
    return 1
  fi

  # Create updated discovery document with all required fields
  cat > /tmp/updated-openid-config.json <<EOF
{
  "issuer": "https://${bucket_name}.s3.${region}.amazonaws.com/cluster/acm-cluster",
  "jwks_uri": "https://${bucket_name}.s3.${region}.amazonaws.com/cluster/acm-cluster/keys.json",
  "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"],
  "claims_supported": ["sub", "iss"]
}
EOF

  # Upload the updated discovery document
  if ! aws s3 cp /tmp/updated-openid-config.json "s3://$bucket_name/cluster/acm-cluster/.well-known/openid-configuration"; then
    echo "❌ Failed to upload updated discovery document"
    return 1
  fi

  echo "✅ OIDC discovery document updated successfully"
  return 0
}

# Process command line arguments
if [ "$3" = "configure_oidc" ]; then
  # If called with configure_oidc command, execute that function
  configure_oidc "$4" "$5"
  exit $?
fi

# create OIDC provider. Uses a fake thumbprint since it's no longer validated when using an S3 bucket
##################################################
echo "🚀 Creating OIDC provider..."
OIDC_PROVIDER_ARN="arn:aws:iam::$AWS_ACCOUNT:oidc-provider/$OIDC_S3_BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/cluster/acm-cluster"
if aws iam create-open-id-connect-provider --url "https://$OIDC_S3_BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/cluster/acm-cluster" --client-id-list 'sts.amazonaws.com' --thumbprint-list "0000000000000000000000000000000000000000" 2>/dev/null; then
	echo "✅ OIDC provider created"
elif aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
	echo "✅ OIDC provider already exists"
else
	echo "❌ Failed to create or access OIDC provider"
	exit 1
fi

# policy for acm-manager
##################################################
echo "🚀 Creating acm-manager IAM policy and role..."
envsubst < "$SCRIPT_DIR/acm-manager-policy.json" >"$policy_file"
envsubst < "$SCRIPT_DIR/acm-manager-assume-policy.json" >"$assume_policy_file"

ACM_POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT:policy/acm-manager"
if policy=$(aws iam create-policy --policy-name acm-manager --policy-document "file://$policy_file" 2>/dev/null); then
	policy_arn=$(echo "$policy" | jq .Policy.Arn -Mr)
	echo "✅ acm-manager policy created"
elif aws iam get-policy --policy-arn "$ACM_POLICY_ARN" >/dev/null 2>&1; then
	policy_arn="$ACM_POLICY_ARN"
	echo "✅ acm-manager policy already exists"
else
	echo "❌ Failed to create or access acm-manager policy"
	exit 1
fi

if aws iam create-role --role-name acm-manager --assume-role-policy-document "file://$assume_policy_file" >/dev/null 2>&1; then
	echo "✅ acm-manager role created"
elif aws iam get-role --role-name acm-manager >/dev/null 2>&1; then
	echo "✅ acm-manager role already exists"
else
	echo "❌ Failed to create or access acm-manager role"
	exit 1
fi

if aws iam attach-role-policy --role-name acm-manager --policy-arn "$policy_arn" 2>/dev/null; then
	echo "✅ acm-manager policy attached to role"
else
	echo "⚠️  Policy may already be attached to role"
fi

# policy for external-dns
##################################################
echo "🚀 Creating external-dns IAM policy and role..."
envsubst < "$SCRIPT_DIR/external-dns-policy.json" >"$policy_file"
envsubst < "$SCRIPT_DIR/external-dns-assume-policy.json" >"$assume_policy_file"

EXTERNAL_DNS_POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT:policy/external-dns"
if policy=$(aws iam create-policy --policy-name external-dns --policy-document "file://$policy_file" 2>/dev/null); then
	policy_arn=$(echo "$policy" | jq .Policy.Arn -Mr)
	echo "✅ external-dns policy created"
elif aws iam get-policy --policy-arn "$EXTERNAL_DNS_POLICY_ARN" >/dev/null 2>&1; then
	policy_arn="$EXTERNAL_DNS_POLICY_ARN"
	echo "✅ external-dns policy already exists"
else
	echo "❌ Failed to create or access external-dns policy"
	exit 1
fi

if aws iam create-role --role-name external-dns --assume-role-policy-document "file://$assume_policy_file" >/dev/null 2>&1; then
	echo "✅ external-dns role created"
elif aws iam get-role --role-name external-dns >/dev/null 2>&1; then
	echo "✅ external-dns role already exists"
else
	echo "❌ Failed to create or access external-dns role"
	exit 1
fi

if aws iam attach-role-policy --role-name external-dns --policy-arn "$policy_arn" 2>/dev/null; then
	echo "✅ external-dns policy attached to role"
else
	echo "⚠️  Policy may already be attached to role"
fi

# create DNS zone
##################################################
if [[ $DNS_ZONE_NAME != "" ]]; then
	aws route53 create-hosted-zone --name "$DNS_ZONE_NAME" --caller-reference "$(date '+%Y%m%d%H%M.%S')"

	echo "**************************************************"
	echo "* You need to configure DNS forwarding if AWS is *"
	echo "* not the authority for this zone                *"
	echo "**************************************************"
fi
