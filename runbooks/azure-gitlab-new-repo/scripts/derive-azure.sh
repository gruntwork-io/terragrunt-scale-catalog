#!/bin/bash
# Automatically derive the Azure tenant and subscription IDs from the confirmed identity,
# so the user never has to type (or mistype) them.
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

RB_out_azure_auth_azure_logged_in=$(rb_unquote "{{ .outputs.azure_auth.azure_logged_in }}")

log_info "Azure login confirmed (${RB_out_azure_auth_azure_logged_in}). Reading your active subscription..."

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ]; then
  log_error "Could not read an active Azure subscription."
  log_error "Run 'az login' and 'az account set --subscription <id>' for the target subscription, then retry."
  exit 1
fi

# Make sure subsequent OpenTofu/Terragrunt runs target this subscription.
az account set --subscription "$SUBSCRIPTION_ID"

{
  echo "azure_subscription_id=${SUBSCRIPTION_ID}"
  echo "azure_tenant_id=${TENANT_ID}"
} >>"$RUNBOOK_OUTPUT"

log_info "Using subscription '${SUBSCRIPTION_NAME}' (${SUBSCRIPTION_ID}) in tenant ${TENANT_ID}."
exit 0
