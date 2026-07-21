#!/bin/bash
# Apply the bootstrap stack. This creates real Azure resources: the state storage account/container/
# resource group and the plan/apply Entra ID applications and role assignments. Review the plan first.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

log_info "Scaffold generated ({{ .outputs.generate_bootstrap.generated }}). Applying the bootstrap stack..."

export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_USE_CLI=true

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Applying in {{ .inputs.SubscriptionName }}/bootstrap (creates state storage + plan/apply Entra ID apps)..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate apply

echo "applied=true" >>"$RUNBOOK_OUTPUT"
log_info "Bootstrap apply complete for subscription {{ .outputs.derive_azure.azure_subscription_id }}."
