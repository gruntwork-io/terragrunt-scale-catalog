#!/bin/bash
# Apply the bootstrap stack. This creates real AWS resources (OIDC provider + IAM roles)
# and the S3 state bucket. Review the plan output above before running this.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES/{{ .inputs.AccountName }}/_global/bootstrap"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply IAM roles now exist in account {{ .outputs.derive_aws.aws_account_id }}."
