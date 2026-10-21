// Root Terragrunt config included by every unit via `find_in_parent_folders("root.hcl")`.
// Configures Azure Storage remote state and generates the Azure provider for all units.
// Docs: https://docs.terragrunt.com/reference/config-blocks-and-attributes/#remote_state

// Read environment-level config from the nearest parent files.
locals {
  sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))

  subscription_id = local.sub_hcl.locals.subscription_id
  location        = local.sub_hcl.locals.location

  state_resource_group_name    = local.sub_hcl.locals.state_resource_group_name
  state_storage_account_name   = local.sub_hcl.locals.state_storage_account_name
  state_storage_container_name = local.sub_hcl.locals.state_storage_container_name
}

remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    subscription_id      = local.subscription_id
    resource_group_name  = local.state_resource_group_name
    storage_account_name = local.state_storage_account_name
    container_name       = local.state_storage_container_name
    key                  = "${path_relative_to_include()}/tofu.tfstate"
    location             = local.location
  }
}

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
