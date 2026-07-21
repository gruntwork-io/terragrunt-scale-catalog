#!/bin/bash
# Verify the expected Pipelines configuration files were generated in the repository.
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

check_file "root.hcl"
check_file ".github/workflows/pipelines.yml"
check_file ".gruntwork/repository.hcl"
check_file ".gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl"
check_file "{{ .inputs.SubscriptionName }}/sub.hcl"
check_file "{{ .inputs.SubscriptionName }}/bootstrap/terragrunt.stack.hcl"

if [ "$rc" -eq 0 ]; then
  log_info "All expected Pipelines configuration files are present."
fi
exit "$rc"
