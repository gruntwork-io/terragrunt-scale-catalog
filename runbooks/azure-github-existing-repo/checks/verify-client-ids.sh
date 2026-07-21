#!/bin/bash
# Confirm the plan/apply client IDs were written into the environment HCL (no empty FIXME values left).
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

ENV_HCL="$REPO_FILES/.gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl"
if [ ! -f "$ENV_HCL" ]; then
  log_error "Missing ${ENV_HCL}"
  exit 1
fi

rc=0
for key in plan_client_id apply_client_id; do
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$ENV_HCL" || true)
  if [ -z "$line" ]; then
    log_error "No ${key} entry found in the environment HCL."
    rc=1
  elif echo "$line" | grep -qE '=[[:space:]]*""'; then
    log_error "${key} is still empty. Did the 'Record the plan/apply client IDs' step run?"
    rc=1
  else
    log_info "${key} is set."
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC client IDs are populated in the environment HCL."
fi
exit "$rc"
