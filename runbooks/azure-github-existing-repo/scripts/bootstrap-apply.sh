#!/bin/bash
# Apply the bootstrap stack. Creates real Azure resources: the state Resource Group / Storage Account /
# Container, and the plan/apply Entra ID applications + service principals + role assignments. Review
# the plan output above before running this. State is local at this point; we migrate it afterwards.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}"

log_info "Applying the bootstrap stack (reusing the stack generated during plan)..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate apply

log_info "Bootstrap apply complete in subscription {{ .outputs.derive_azure.azure_subscription_id }}."
