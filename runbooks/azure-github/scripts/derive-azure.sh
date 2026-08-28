#!/bin/bash
# Automatically derive the Azure tenant and subscription IDs from your active `az login` session, so you
# never have to look them up by hand. Also exports ARM_TENANT_ID / ARM_SUBSCRIPTION_ID for the Terragrunt
# steps that follow — these env vars are how the azurerm/azuread providers pick the target subscription.
set -euo pipefail

log_info "Deriving Azure tenant and subscription IDs from your active az session..."
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

if [ -z "$TENANT_ID" ] || [ -z "$SUBSCRIPTION_ID" ]; then
  log_error "Could not read tenant/subscription from az. Run the 'Sign in with az login' step and select a subscription first."
  exit 1
fi

# Persist for later Terragrunt blocks in this session.
export ARM_TENANT_ID="$TENANT_ID"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

{
  echo "azure_tenant_id=${TENANT_ID}"
  echo "azure_subscription_id=${SUBSCRIPTION_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Tenant ${TENANT_ID}, subscription ${SUBSCRIPTION_ID}."
exit 0
