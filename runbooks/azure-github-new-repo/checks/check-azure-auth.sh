#!/bin/bash
# Confirm the Azure CLI is authenticated and can reach the active subscription.
# Gated on the az login step having run (references its output below).
set -uo pipefail

# Ordering guard: this check is enabled only after the az login step has completed.
AZ_LOGIN_DONE="{{ .outputs.az_login.azure_logged_in }}"
log_info "Verifying Azure CLI authentication (login step reported: ${AZ_LOGIN_DONE})..."

if az account show >/dev/null 2>&1; then
  SUB_NAME=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
  SUB_ID=$(az account show --query id -o tsv 2>/dev/null || echo "unknown")
  log_info "Azure CLI is authenticated. Active subscription: ${SUB_NAME} (${SUB_ID})."
  echo "azure_authenticated=true" >> "$RUNBOOK_OUTPUT"
  exit 0
else
  log_error "The Azure CLI is not authenticated. Re-run the 'Azure CLI login' step and complete the sign-in."
  exit 1
fi
