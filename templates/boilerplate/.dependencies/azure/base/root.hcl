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
