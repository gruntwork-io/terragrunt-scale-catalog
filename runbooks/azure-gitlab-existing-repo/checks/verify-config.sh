#!/bin/bash
# Verify the expected Pipelines configuration files were generated in the repository and that the
# environment HCL has real (non-placeholder) plan/apply client IDs.
set -uo pipefail

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

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")

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
check_file ".gruntwork/environment-${RB_SubscriptionName}.hcl"
check_file "${RB_SubscriptionName}/bootstrap/terragrunt.stack.hcl"

ENV_HCL=".gruntwork/environment-${RB_SubscriptionName}.hcl"
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
