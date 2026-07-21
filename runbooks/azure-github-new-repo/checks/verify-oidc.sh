#!/bin/bash
# Confirm the plan/apply Entra ID applications created by the bootstrap stack exist in the tenant.
set -uo pipefail

PREFIX="{{ .inputs.OIDCResourcePrefix }}"
rc=0
for app in "${PREFIX}-plan" "${PREFIX}-apply"; do
  count=$(az ad app list --display-name "$app" --query 'length(@)' -o tsv 2>/dev/null || echo 0)
  if [ "${count:-0}" -ge 1 ]; then
    log_info "Entra ID application ${app} exists."
  else
    log_error "Entra ID application ${app} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both plan/apply Entra ID applications are present."
fi
exit "$rc"
