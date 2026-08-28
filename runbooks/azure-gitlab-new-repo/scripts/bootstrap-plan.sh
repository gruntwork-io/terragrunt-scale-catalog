#!/bin/bash
# Plan the bootstrap stack: the Azure state storage plus the plan/apply Entra ID applications,
# service principals, custom roles, and federated identity credentials.
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

log_info "Scaffold generated (${RB_out_generate_bootstrap_generated}). Planning the bootstrap stack..."

# OpenTofu's azurerm/azuread providers authenticate via the Azure CLI login cached earlier.
export ARM_SUBSCRIPTION_ID="${RB_out_derive_azure_azure_subscription_id}"
export ARM_TENANT_ID="${RB_out_derive_azure_azure_tenant_id}"
export ARM_USE_CLI=true

cd "$REPO_FILES/${RB_SubscriptionName}/bootstrap"

log_info "Planning in ${RB_SubscriptionName}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache plan
