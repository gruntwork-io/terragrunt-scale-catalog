#!/bin/bash
# Migrate the bootstrap state from the local backend into the newly-created Azure Blob Storage. Runs
# after remote_state has been activated in root.hcl.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}"

log_info "Migrating bootstrap state into the Azure Blob Storage backend..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate -- init -migrate-state -force-copy

log_info "State migration complete. Bootstrap state now lives in the azurerm backend."
exit 0
