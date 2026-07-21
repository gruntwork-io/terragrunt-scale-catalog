#!/bin/bash
# Confirm the plan/apply Entra ID applications created by the bootstrap stack exist in the directory.
set -uo pipefail

PLAN_ID="{{ .outputs.capture_client_ids.plan_client_id }}"
APPLY_ID="{{ .outputs.capture_client_ids.apply_client_id }}"

rc=0
for pair in "plan:${PLAN_ID}" "apply:${APPLY_ID}"; do
  name="${pair%%:*}"
  id="${pair#*:}"
  if [ -z "$id" ]; then
    log_error "No ${name} client ID was captured. Did the 'Capture the plan/apply client IDs' step run?"
    rc=1
    continue
  fi
  if az ad app show --id "$id" >/dev/null 2>&1; then
    log_info "Entra ID ${name} application ${id} exists."
  else
    log_error "Entra ID ${name} application ${id} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC applications are present."
fi
exit "$rc"
