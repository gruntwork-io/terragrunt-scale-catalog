#!/bin/bash
# Confirm the plan/apply IAM roles created by the bootstrap stack exist in the account.
set -uo pipefail

PREFIX="{{ .inputs.OIDCResourcePrefix }}"
rc=0
for role in "${PREFIX}-plan" "${PREFIX}-apply"; do
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    log_info "IAM role ${role} exists."
  else
    log_error "IAM role ${role} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC IAM roles are present."
fi
exit "$rc"
