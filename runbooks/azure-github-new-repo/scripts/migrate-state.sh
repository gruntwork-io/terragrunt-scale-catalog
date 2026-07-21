#!/bin/bash
# Migrate the OpenTofu state for the bootstrap stack from local disk into the Azure Blob Storage backend
# that the apply step just created. Now that remote_state is active in root.hcl, re-initializing with
# -migrate-state copies the existing local state up to the storage account. --no-stack-generate reuses the
# already-applied stack so the local state directories (and their state) are preserved.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"

# Ordering guards: enabled only after remote state is active and the client IDs are recorded.
REMOTE_STATE_DONE="{{ .outputs.enable_remote_state.remote_state_enabled }}"
CLIENT_IDS_DONE="{{ .outputs.capture_client_ids.client_ids_written }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Migrating OpenTofu state to Azure Blob Storage (remote state: ${REMOTE_STATE_DONE}, client IDs: ${CLIENT_IDS_DONE})..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate -- init -migrate-state -force-copy

log_info "State migration complete. Remote state now lives in the Azure storage account."
