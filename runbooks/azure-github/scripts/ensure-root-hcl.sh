#!/bin/bash
# Ensure the repository root has a Terragrunt Scale root.hcl configured for Azure. The subscription
# template does NOT create root.hcl (that content lives in the azure/base layer used only for brand-new
# repos), so for an existing repo we add the same content here: the azurerm/azuread provider generation
# plus a remote_state block that stays commented out until state is bootstrapped and migrated.
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

RB_out_inspect_repository_repo_mode=$(rb_unquote "{{ .outputs.inspect_repository.repo_mode }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

if [ "$RB_out_inspect_repository_repo_mode" = "scaffold" ]; then
  log_info "The repository scaffold already rendered root.hcl; nothing to ensure."
  exit 0
fi

ROOT_HCL="$REPO_FILES/root.hcl"

if [ -f "$ROOT_HCL" ] && grep -q 'remote_state' "$ROOT_HCL"; then
  log_info "root.hcl already contains a remote_state block; leaving it unchanged."
  exit 0
fi

if [ -f "$ROOT_HCL" ] && [ -s "$ROOT_HCL" ]; then
  log_warn "root.hcl exists but has no remote_state block. Appending the Azure root configuration."
  log_warn "Review root.hcl afterwards for any duplicate locals/generate blocks."
  printf '\n' >> "$ROOT_HCL"
else
  log_info "Creating root.hcl with the Azure root configuration."
fi

cat >> "$ROOT_HCL" <<'ROOT_HCL_EOF'
// Root Terragrunt config included by every unit via `find_in_parent_folders("root.hcl")`.
// Generates the Azure provider for all units. Remote state is commented out until after bootstrap.
// Docs: https://docs.terragrunt.com/reference/config-blocks-and-attributes/#remote_state

// Read environment-level config from the nearest parent files.
locals {
  sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))

  state_resource_group_name    = local.sub_hcl.locals.state_resource_group_name
  state_storage_account_name   = local.sub_hcl.locals.state_storage_account_name
  state_storage_container_name = local.sub_hcl.locals.state_storage_container_name
}

# FIXME: Uncomment the code below when you've successfully bootstrapped Pipelines state.
#
# remote_state {
#   backend = "azurerm"
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite"
#   }
#   config = {
#     resource_group_name  = local.state_resource_group_name
#     storage_account_name = local.state_storage_account_name
#     container_name       = local.state_storage_container_name
#     key                  = "${path_relative_to_include()}/tofu.tfstate"
#   }
# }

// Generates provider.tf in each unit at plan/apply time.
// `resource_provider_registrations = "none"` prevents the provider from auto-registering resource providers, which needs elevated permissions.
// Docs: https://search.opentofu.org/provider/terraform-providers/azurerm/latest
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
ROOT_HCL_EOF

log_info "root.hcl is in place. The remote_state block is commented out and will be enabled after bootstrap."
exit 0
