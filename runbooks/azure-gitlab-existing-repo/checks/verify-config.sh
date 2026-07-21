#!/bin/bash
# Verify the expected Pipelines configuration files were generated in the repository and that the
# environment HCL has real (non-placeholder) plan/apply client IDs.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

cd "$REPO_FILES"
rc=0

check_file() {
  if [ -f "$1" ]; then
    log_info "Found $1"
  else
    log_error "Missing $1"
    rc=1
  fi
}

check_file ".gitlab-ci.yml"
check_file ".gruntwork/repository.hcl"
check_file ".gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl"
check_file "{{ .inputs.SubscriptionName }}/bootstrap/terragrunt.stack.hcl"

ENV_HCL=".gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl"
if [ -f "$ENV_HCL" ]; then
  if grep -q "FIXME" "$ENV_HCL" || grep -Eq '(plan|apply)_client_id[[:space:]]*=[[:space:]]*""' "$ENV_HCL"; then
    log_error "$ENV_HCL still has empty/FIXME client IDs. Re-run the 'Capture the plan/apply client IDs' step."
    rc=1
  else
    log_info "$ENV_HCL has non-empty plan/apply client IDs."
  fi
fi

if [ "$rc" -eq 0 ]; then
  log_info "All expected Pipelines configuration files are present and complete."
fi
exit "$rc"
