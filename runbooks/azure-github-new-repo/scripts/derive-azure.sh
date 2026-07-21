#!/bin/bash
# Automatically derive the Azure tenant and subscription IDs from the active 'az' account, so the user
# never has to look them up by hand. These populate the environment HCL and the bootstrap stack, and are
# exported as ARM_* for the azurerm/azuread providers during the provisioning steps.
set -euo pipefail

# Ordering guard: enabled only after Azure authentication is confirmed.
AZURE_AUTH="{{ .outputs.check_azure_auth.azure_authenticated }}"
log_info "Deriving the Azure tenant and subscription IDs from your active account (auth confirmed: ${AZURE_AUTH})..."

TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

if [ -z "$TENANT_ID" ] || [ -z "$SUBSCRIPTION_ID" ]; then
  log_error "Could not resolve the tenant/subscription ID. Confirm 'az account show' returns an active subscription."
  exit 1
fi

{
  echo "azure_tenant_id=${TENANT_ID}"
  echo "azure_subscription_id=${SUBSCRIPTION_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Tenant ${TENANT_ID}, subscription ${SUBSCRIPTION_ID}."
exit 0
