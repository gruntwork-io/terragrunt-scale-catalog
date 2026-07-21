#!/bin/bash
# Plan the bootstrap stack: the Azure state storage plus the plan/apply Entra ID applications,
# service principals, custom roles, and federated identity credentials.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

log_info "Scaffold generated ({{ .outputs.generate_bootstrap.generated }}). Planning the bootstrap stack..."

# OpenTofu's azurerm/azuread providers authenticate via the Azure CLI login cached earlier.
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_USE_CLI=true

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Planning in {{ .inputs.SubscriptionName }}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache plan
