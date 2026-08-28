#!/bin/bash
# Apply the bootstrap stack. This creates real AWS resources (OIDC provider + IAM roles)
# and the S3 state bucket. Review the plan output above before running this.
set -euo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and a single pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_AccountName=$(rb_unquote "{{ .inputs.AccountName }}")
RB_out_derive_aws_aws_account_id=$(rb_unquote "{{ .outputs.derive_aws.aws_account_id }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Temporary AWS credentials routinely expire part-way through this runbook — it is long, and the
# gap between steps is however long you were away. Check reachability first so an expired session
# says so plainly here, instead of surfacing as a confusing failure further in.
if ! aws_account=$(aws sts get-caller-identity --output text --query 'Account' 2>&1); then
  log_error "Could not reach AWS with the current credentials: ${aws_account}"
  log_error "Re-run the AWS authentication step above to refresh them, then run this step again."
  exit 1
fi
log_info "Authenticated to AWS account ${aws_account}."

cd "$REPO_FILES/${RB_AccountName}/_global/bootstrap"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply IAM roles now exist in account ${RB_out_derive_aws_aws_account_id}."
