#!/bin/bash
# Migrate the local bootstrap state into the Azure Blob Storage backend now that remote_state is enabled.
# Re-initializes each unit with the azurerm backend and copies the existing local state up.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the enable-remote-state output gates this block until the backend has been uncommented.
: "{{ .outputs.enable_remote_state.remote_state_enabled }}"

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Migrating bootstrap state into the Azure Blob backend..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate -- init -migrate-state -force-copy

echo "state_migrated=true" >> "$RUNBOOK_OUTPUT"
log_info "State migration complete. Bootstrap state now lives in the Azure storage account."
