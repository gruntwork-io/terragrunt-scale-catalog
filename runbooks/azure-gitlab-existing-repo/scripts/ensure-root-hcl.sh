#!/bin/bash
# Ensure the repository root.hcl declares the Azure azurerm/azuread providers and an azurerm remote-state
# backend. In an existing Terragrunt Scale repo these are usually already present, in which case this is a
# no-op. If they are missing (or root.hcl does not exist), append/write the canonical blocks. The
# remote-state backend is written COMMENTED OUT so the first bootstrap can run against local state; a
# later step uncomments it once the state storage account exists.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the generate output gates this block until the bootstrap config (sub.hcl) has been rendered.
: "{{ .outputs.generate_bootstrap.generated }}"

ROOT_HCL="$REPO_FILES/root.hcl"

read -r -d '' AZURE_BLOCK <<'HCL' || true
// --- Gruntwork Pipelines: Azure remote state backend and providers ---
// Reads the per-subscription state storage config from sub.hcl.
locals {
  _pipelines_sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))

  _pipelines_state_resource_group_name    = local._pipelines_sub_hcl.locals.state_resource_group_name
  _pipelines_state_storage_account_name   = local._pipelines_sub_hcl.locals.state_storage_account_name
  _pipelines_state_storage_container_name = local._pipelines_sub_hcl.locals.state_storage_container_name
}

# FIXME: Uncomment the code below when you've successfully bootstrapped Pipelines state.
# The runbook uncomments this automatically after the bootstrap apply succeeds.
# remote_state {
#   backend = "azurerm"
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite"
#   }
#   config = {
#     resource_group_name  = local._pipelines_state_resource_group_name
#     storage_account_name = local._pipelines_state_storage_account_name
#     container_name       = local._pipelines_state_storage_container_name
#     key                  = "${path_relative_to_include()}/tofu.tfstate"
#   }
# }

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
}

provider "azuread" {}
EOF
}
HCL

if [ ! -f "$ROOT_HCL" ]; then
  log_warn "No root.hcl found; scaffolding the Azure backend and providers."
  printf '%s\n' "$AZURE_BLOCK" > "$ROOT_HCL"
  log_info "Wrote root.hcl with the Azure backend (commented) and providers."
  exit 0
fi

if grep -q 'backend = "azurerm"' "$ROOT_HCL" || grep -Eq 'provider[[:space:]]+"azuread"' "$ROOT_HCL"; then
  log_info "root.hcl already configures the Azure backend/providers; leaving it unchanged."
  exit 0
fi

log_warn "root.hcl is missing the Azure backend/providers; appending them."
{ echo ""; printf '%s\n' "$AZURE_BLOCK"; } >> "$ROOT_HCL"
log_info "Appended the Azure backend (commented) and providers to root.hcl."
exit 0
