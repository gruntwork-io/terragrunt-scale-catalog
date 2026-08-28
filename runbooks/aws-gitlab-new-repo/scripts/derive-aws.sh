#!/bin/bash
# Automatically derive the AWS account ID and partition from the confirmed AWS identity,
# so the user never has to type (or mistype) their account number.
set -euo pipefail

log_info "Deriving AWS account ID and partition from your authenticated identity..."

# One call, checked. Temporary credentials lapse often enough mid-runbook that an unchecked
# failure here reads as "the runbook broke" rather than "your session expired".
if ! identity=$(aws sts get-caller-identity --output text --query '[Arn,Account]' 2>&1); then
  log_error "Could not reach AWS with the current credentials: ${identity}"
  log_error "Re-run the AWS authentication step above to refresh them, then run this step again."
  exit 1
fi
ARN=$(printf '%s' "$identity" | awk '{print $1}')
ACCOUNT_ID=$(printf '%s' "$identity" | awk '{print $2}')

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
