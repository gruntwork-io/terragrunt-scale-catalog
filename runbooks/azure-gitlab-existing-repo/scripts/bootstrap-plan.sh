#!/bin/bash
# Plan the bootstrap stack: the Entra ID plan/apply applications, federated credentials, custom roles,
# role assignments, and the Azure Blob state storage. This generates the stack and plans against local
# state (the remote backend is not enabled until the state storage account exists).
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
RB_out_generate_bootstrap_generated=$(rb_unquote "{{ .outputs.generate_bootstrap.generated }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the generate output gates this block until the bootstrap config has been rendered.
: "${RB_out_generate_bootstrap_generated}"

export ARM_TENANT_ID="${RB_out_derive_azure_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_derive_azure_azure_subscription_id}"

cd "$REPO_FILES/${RB_SubscriptionName}/bootstrap"

log_info "Planning the bootstrap stack in ${RB_SubscriptionName}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache plan

echo "planned=true" >> "$RUNBOOK_OUTPUT"
