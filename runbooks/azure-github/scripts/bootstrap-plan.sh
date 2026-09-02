#!/bin/bash
# Plan the bootstrap stack: the plan/apply Entra ID applications, service principals, federated identity
# credentials, custom roles/assignments, and the Azure Blob Storage state-backend resources.
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
RB_out_read_details_azure_subscription_id=$(rb_unquote "{{ .outputs.read_details.azure_subscription_id }}")
RB_out_read_details_azure_tenant_id=$(rb_unquote "{{ .outputs.read_details.azure_tenant_id }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Belt-and-suspenders: make sure the azurerm/azuread providers target the derived subscription/tenant.
export ARM_TENANT_ID="${RB_out_read_details_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_read_details_azure_subscription_id}"

cd "$REPO_FILES/${RB_SubscriptionName}"

log_info "Planning the bootstrap stack under ${RB_SubscriptionName}/ ..."
terragrunt run --all --non-interactive --provider-cache plan
