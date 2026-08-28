#!/bin/bash
# Automatically derive the Azure tenant ID and subscription ID from the active `az` session, so the
# user never has to type (or mistype) them. These populate the environment config and ARM_* variables.
set -euo pipefail

# Values substituted into this script can arrive wrapped in quotes; strip them before use.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_out_azure_login_account_name=$(rb_unquote "{{ .outputs.azure_login.account_name }}")

# Referencing the sign-in output gates this block until the Azure sign-in step has run.
: "${RB_out_azure_login_account_name}"

log_info "Reading tenant and subscription IDs from your active Azure session..."
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

if [ -z "$TENANT_ID" ] || [ -z "$SUBSCRIPTION_ID" ]; then
  log_error "Could not read the tenant/subscription IDs. Complete the Azure sign-in step first."
  exit 1
fi

{
  echo "azure_tenant_id=${TENANT_ID}"
  echo "azure_subscription_id=${SUBSCRIPTION_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Tenant ${TENANT_ID}, subscription ${SUBSCRIPTION_ID}."
exit 0
