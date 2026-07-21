#!/bin/bash
# Verify the expected repository scaffold and Pipelines configuration files were generated, that the
# azurerm remote state is active, and that the plan/apply client IDs were recorded.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

cd "$REPO_FILES"
SUB="{{ .inputs.SubscriptionName }}"
rc=0
warn=0

check_file() {
  if [ -f "$1" ]; then
    log_info "Found $1"
  else
    log_error "Missing $1"
    rc=1
  fi
}

check_file "root.hcl"
check_file ".mise.toml"
check_file ".gruntwork/repository.hcl"
check_file ".gruntwork/environment-${SUB}.hcl"
check_file "${SUB}/sub.hcl"
check_file "${SUB}/bootstrap/terragrunt.stack.hcl"

if [ "$rc" -eq 0 ]; then
  if grep -q '^remote_state {' root.hcl; then
    log_info "The azurerm remote_state block is active in root.hcl."
  else
    log_warn "remote_state is still commented out in root.hcl. Run the 'Enable the azurerm remote state' step."
    warn=1
  fi

  if grep -q 'FIXME: Fill in the client ID' ".gruntwork/environment-${SUB}.hcl"; then
    log_warn "environment-${SUB}.hcl still has FIXME client IDs. Run the 'Record the plan/apply client IDs' step."
    warn=1
  else
    log_info "The plan/apply client IDs are populated in environment-${SUB}.hcl."
  fi
fi

if [ "$rc" -ne 0 ]; then
  exit 1
fi
if [ "$warn" -ne 0 ]; then
  exit 2
fi

log_info "All expected repository scaffold files are present and fully populated."
exit 0
