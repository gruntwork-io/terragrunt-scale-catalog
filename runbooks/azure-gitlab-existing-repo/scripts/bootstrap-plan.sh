#!/bin/bash
# Plan the bootstrap stack: the Entra ID plan/apply applications, federated credentials, custom roles,
# role assignments, and the Azure Blob state storage. This generates the stack and plans against local
# state (the remote backend is not enabled until the state storage account exists).
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the generate output gates this block until the bootstrap config has been rendered.
: "{{ .outputs.generate_bootstrap.generated }}"

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

cd "$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"

log_info "Planning the bootstrap stack in {{ .inputs.SubscriptionName }}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache plan

echo "planned=true" >> "$RUNBOOK_OUTPUT"
