#!/bin/bash
# Uncomment the remote_state block in root.hcl (the state storage now exists) and migrate the
# bootstrap state from local disk into Azure Blob Storage.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

log_info "Client IDs written ({{ .outputs.capture_client_ids.client_ids_written }}). Enabling remote state..."

export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_USE_CLI=true

SUB="{{ .inputs.SubscriptionName }}"
ROOT_HCL="$REPO_FILES/root.hcl"

if [ ! -f "$ROOT_HCL" ]; then
  log_error "root.hcl not found at ${ROOT_HCL}."
  exit 1
fi

log_info "Uncommenting the remote_state block in root.hcl..."
# Drop the FIXME instruction lines, then strip the leading '# ' from the commented remote_state block.
awk '
  /^# FIXME: Uncomment the code below/ { region=1; next }
  region && /^#$/ { next }
  region && /^#/ {
    sub(/^# ?/, "")
    print
    if ($0 ~ /^\}$/) { region=0 }
    next
  }
  { print }
' "$ROOT_HCL" >"${ROOT_HCL}.tmp" && mv "${ROOT_HCL}.tmp" "$ROOT_HCL"

if grep -q '^# remote_state' "$ROOT_HCL"; then
  log_error "Failed to uncomment the remote_state block; please edit root.hcl manually."
  exit 1
fi
log_info "remote_state backend enabled in root.hcl."

cd "$REPO_FILES/${SUB}/bootstrap"

log_info "Migrating bootstrap state from local to Azure Blob Storage..."
# --no-stack-generate reuses the already-applied stack so the local state is preserved and copied up.
terragrunt run --all --non-interactive --provider-cache --no-stack-generate -- init -migrate-state -force-copy

echo "remote_state_enabled=true" >>"$RUNBOOK_OUTPUT"
log_info "Remote state configured and bootstrap state migrated to Azure Blob Storage."
