#!/usr/bin/env bash

set -e

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

if [[ $AWS_REGION == "" ]]; then
	AWS_REGION=$(aws configure get region)
fi

AWS_ACCOUNT=$(aws sts get-caller-identity | jq '.Account' -Mr)
acm_policy_arn="arn:aws:iam::$AWS_ACCOUNT:policy/acm-manager"
external_dns_policy_arn="arn:aws:iam::$AWS_ACCOUNT:policy/external-dns"

echo "🧹 Cleaning up AWS resources..."

# policy for acm-manager
##################################################
echo "🚀 Cleaning up acm-manager IAM resources..."
if aws iam get-role --role-name acm-manager >/dev/null 2>&1; then
	if aws iam detach-role-policy --role-name acm-manager --policy-arn "$acm_policy_arn" 2>/dev/null; then
		echo "✅ Detached acm-manager policy from role"
	else
		echo "⚠️  Policy may not be attached to role"
	fi

	if aws iam delete-role --role-name acm-manager 2>/dev/null; then
		echo "✅ Deleted acm-manager role"
	else
		echo "❌ Failed to delete acm-manager role"
	fi
else
	echo "⚠️  acm-manager role does not exist"
fi

if aws iam get-policy --policy-arn "$acm_policy_arn" >/dev/null 2>&1; then
	if aws iam delete-policy --policy-arn "$acm_policy_arn" 2>/dev/null; then
		echo "✅ Deleted acm-manager policy"
	else
		echo "❌ Failed to delete acm-manager policy"
	fi
else
	echo "⚠️  acm-manager policy does not exist"
fi

# policy for external-dns
##################################################
echo "🚀 Cleaning up external-dns IAM resources..."
if aws iam get-role --role-name external-dns >/dev/null 2>&1; then
	if aws iam detach-role-policy --role-name external-dns --policy-arn "$external_dns_policy_arn" 2>/dev/null; then
		echo "✅ Detached external-dns policy from role"
	else
		echo "⚠️  Policy may not be attached to role"
	fi

	if aws iam delete-role --role-name external-dns 2>/dev/null; then
		echo "✅ Deleted external-dns role"
	else
		echo "❌ Failed to delete external-dns role"
	fi
else
	echo "⚠️  external-dns role does not exist"
fi

if aws iam get-policy --policy-arn "$external_dns_policy_arn" >/dev/null 2>&1; then
	if aws iam delete-policy --policy-arn "$external_dns_policy_arn" 2>/dev/null; then
		echo "✅ Deleted external-dns policy"
	else
		echo "❌ Failed to delete external-dns policy"
	fi
else
	echo "⚠️  external-dns policy does not exist"
fi

# delete OIDC provider configuration
##################################################
echo "🚀 Cleaning up OIDC provider..."
OIDC_PROVIDER_ARN="arn:aws:iam::$AWS_ACCOUNT:oidc-provider/$OIDC_S3_BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/cluster/acm-cluster"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
	if aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" 2>/dev/null; then
		echo "✅ Deleted OIDC provider"
	else
		echo "❌ Failed to delete OIDC provider"
	fi
else
	echo "⚠️  OIDC provider does not exist"
fi

# clean OIDC bucket
##################################################
echo "🚀 Cleaning up S3 bucket..."
if aws s3api head-bucket --bucket "$OIDC_S3_BUCKET_NAME" 2>/dev/null; then
	echo "🧹 Removing OIDC configuration files..."

	# Remove specific OIDC files first to ensure complete cleanup
	aws s3 rm "s3://$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/keys.json" 2>/dev/null
	aws s3 rm "s3://$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/openid/v1/jwks" 2>/dev/null
	aws s3 rm "s3://$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/.well-known/openid-configuration" 2>/dev/null

	# Remove all remaining objects in the cluster directory
	if aws s3 rm "s3://$OIDC_S3_BUCKET_NAME/cluster" --recursive 2>/dev/null; then
		echo "✅ Cleaned S3 bucket contents"
	else
		echo "⚠️  S3 bucket may already be empty"
	fi

	# Remove bucket policy before attempting to delete bucket
	echo "🧹 Removing bucket policy..."
	aws s3api delete-bucket-policy --bucket "$OIDC_S3_BUCKET_NAME" 2>/dev/null

	# Attempt to delete the bucket
	if aws s3api delete-bucket --bucket "$OIDC_S3_BUCKET_NAME" 2>/dev/null; then
		echo "✅ Deleted S3 bucket"
	else
		echo "❌ Failed to delete S3 bucket (may not be empty)"

		# List any remaining objects for debugging
		echo "🔍 Checking for remaining objects..."
		aws s3 ls "s3://$OIDC_S3_BUCKET_NAME" --recursive
	fi
else
	echo "⚠️  S3 bucket does not exist"
fi

# delete DNS zone
##################################################
if [[ $DNS_ZONE_NAME != "" ]]; then
	dns_zone=$DNS_ZONE_NAME
	if [[ ${dns_zone: -1} != '.' ]]; then
		dns_zone="$dns_zone".
	fi
	zone_id=$(aws route53 list-hosted-zones-by-name | jq ".HostedZones[] | select(.Name == \"$dns_zone\") | .Id" -Mr)
	aws route53 delete-hosted-zone --id="$zone_id"
fi
