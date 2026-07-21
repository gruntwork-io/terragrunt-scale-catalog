#!/bin/bash
# Plan the bootstrap stack: the plan/apply Entra ID applications, service principals, federated identity
# credentials, custom roles/assignments, and the Azure Blob Storage state-backend resources.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Belt-and-suspenders: make sure the azurerm/azuread providers target the derived subscription/tenant.
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}"

log_info "Planning the bootstrap stack under {{ .inputs.SubscriptionName }}/ ..."
terragrunt run --all --non-interactive --provider-cache plan
