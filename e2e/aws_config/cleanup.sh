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

AWS_ACCOUNT=$(aws sts get-caller-identity | jq '.Account' -Mr)
policy_arn="arn:aws:iam::$AWS_ACCOUNT:policy/acm-manager"

# policy for acm-manager
##################################################
aws iam detach-role-policy --role-name acm-manager --policy-arn "$policy_arn"
aws iam delete-role --role-name acm-manager
aws iam delete-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT:policy/acm-manager"

# policy for external-dns
##################################################
aws iam detach-role-policy --role-name external-dns --policy-arn "$policy_arn"
aws iam delete-role --role-name external-dns
aws iam delete-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT:policy/external-dns"

# delete OIDC provider configuration
##################################################
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::$AWS_ACCOUNT:oidc-provider/$OIDC_S3_BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/cluster/acm-cluster"

# clean OIDC bucket
##################################################
aws s3 rm "s3://$OIDC_S3_BUCKET_NAME/cluster" --recursive
aws s3api delete-bucket --bucket "$OIDC_S3_BUCKET_NAME"

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
