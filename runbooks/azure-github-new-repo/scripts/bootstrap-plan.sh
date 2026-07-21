#!/bin/bash
# Plan the bootstrap stack: the plan/apply Entra ID applications, service principals, role assignments,
# and the Azure Blob Storage state backend. The root.hcl azurerm backend is still commented out at this
# point, so this runs against local OpenTofu state.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Pin the azurerm/azuread providers to the derived tenant/subscription.
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"

# Ordering guard: enabled only after the scaffold has been generated.
SCAFFOLD_DONE="{{ .outputs.generate_scaffold.scaffold_generated }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Planning the bootstrap stack in {{ .inputs.SubscriptionName }}/bootstrap (scaffold: ${SCAFFOLD_DONE})..."
terragrunt run --all --non-interactive --provider-cache plan

echo "plan_complete=true" >> "$RUNBOOK_OUTPUT"
