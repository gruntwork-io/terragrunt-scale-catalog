#!/bin/bash
# Migrate the local bootstrap state into the Azure Blob Storage backend now that remote_state is enabled.
# Re-initializes each unit with the azurerm backend and copies the existing local state up.
set -euo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and a single pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_out_derive_azure_azure_subscription_id=$(rb_unquote "{{ .outputs.derive_azure.azure_subscription_id }}")
RB_out_derive_azure_azure_tenant_id=$(rb_unquote "{{ .outputs.derive_azure.azure_tenant_id }}")
RB_out_enable_remote_state_remote_state_enabled=$(rb_unquote "{{ .outputs.enable_remote_state.remote_state_enabled }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the enable-remote-state output gates this block until the backend has been uncommented.
: "${RB_out_enable_remote_state_remote_state_enabled}"

export ARM_TENANT_ID="${RB_out_derive_azure_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_derive_azure_azure_subscription_id}"

cd "$REPO_FILES/${RB_SubscriptionName}/bootstrap"

log_info "Migrating bootstrap state into the Azure Blob backend..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate -- init -migrate-state -force-copy

echo "state_migrated=true" >> "$RUNBOOK_OUTPUT"
log_info "State migration complete. Bootstrap state now lives in the Azure storage account."
