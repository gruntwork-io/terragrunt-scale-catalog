#!/bin/bash
# Automatically derive the AWS account ID and partition from the confirmed AWS identity,
# so the user never has to type (or mistype) their account number.
set -euo pipefail

log_info "Deriving AWS account ID and partition from your authenticated identity..."
ARN=$(aws sts get-caller-identity --query Arn --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

case "$ARN" in
  arn:aws-us-gov:*) PARTITION="aws-us-gov" ;;
  arn:aws-cn:*)     PARTITION="aws-cn" ;;
  *)                PARTITION="aws" ;;
esac

{
  echo "aws_account_id=${ACCOUNT_ID}"
  echo "partition=${PARTITION}"
} >> "$RUNBOOK_OUTPUT"

log_info "Account ID ${ACCOUNT_ID} in partition ${PARTITION}."
exit 0
