#!/bin/bash
# Apply the bootstrap stack. This creates real Azure resources (Entra ID applications, service principals,
# federated credentials, custom roles, role assignments) and the state storage account. State remains
# local until the migrate-state step. Review the plan output above before running this.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the plan output gates this block until the plan step has run.
: "{{ .outputs.bootstrap_plan.planned }}"

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Applying the bootstrap stack (state remains local until migration)..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate apply

echo "applied=true" >> "$RUNBOOK_OUTPUT"

log_info "Bootstrap apply complete. The Entra ID applications and state storage now exist in subscription {{ .outputs.derive_azure.azure_subscription_id }}."
