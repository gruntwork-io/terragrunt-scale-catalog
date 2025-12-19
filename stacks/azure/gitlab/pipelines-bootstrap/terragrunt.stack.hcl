locals {
  // Source resolution
  terragrunt_scale_catalog_url = try(values.terragrunt_scale_catalog_url, "github.com/gruntwork-io/terragrunt-scale-catalog")
  terragrunt_scale_catalog_ref = try(values.terragrunt_scale_catalog_ref, "v1.3.1")

  // State values
  location = values.location

  state_resource_group_name    = values.state_resource_group_name
  state_storage_account_name   = values.state_storage_account_name
  state_storage_container_name = try(values.state_storage_container_name, "tfstate")

  // OIDC values
  oidc_resource_prefix = try(values.oidc_resource_prefix, "pipelines")

  gitlab_server_domain = try(values.gitlab_server_domain, "gitlab.com")

  default_issuer = "https://${local.gitlab_server_domain}"

  issuer = try(values.issuer, local.default_issuer)

  gitlab_group_name   = try(values.gitlab_group_name, "")
  gitlab_project_name = try(values.gitlab_project_name, "")

  audiences = try(values.audiences, ["https://${local.gitlab_server_domain}/${local.gitlab_group_name}"])

  deploy_branch = try(values.deploy_branch, "main")

  plan_service_principal_to_sub_role_definition_assignment = try(
    values.plan_service_principal_to_sub_role_definition_assignment,
    "Reader",
  )
  plan_service_principal_to_state_role_definition_assignment = try(
    values.plan_service_principal_to_state_role_definition_assignment,
    "Contributor",
  )
  apply_service_principal_to_state_role_definition_assignment = try(
    values.apply_service_principal_to_state_role_definition_assignment,
    "Contributor",
  )

  default_plan_custom_role_actions = [
    "*/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/deployments/read",
    "Microsoft.Resources/deployments/operations/read",
    "Microsoft.Storage/storageAccounts/listKeys/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/read",
  ]

  default_apply_custom_role_actions = [
    "*/read",
    "Microsoft.Resources/subscriptions/resourceGroups/*",
    "Microsoft.Resources/deployments/*",
    "Microsoft.Storage/storageAccounts/*",
    "Microsoft.Storage/storageAccounts/blobServices/*",
    "Microsoft.Storage/storageAccounts/blobServices/containers/*",
    "Microsoft.Storage/storageAccounts/fileServices/*",
    "Microsoft.Storage/storageAccounts/queueServices/*",
    "Microsoft.Storage/storageAccounts/tableServices/*",
    "Microsoft.Authorization/roleAssignments/*",
    "Microsoft.Authorization/roleDefinitions/*",
    "Microsoft.Authorization/locks/read",
    "Microsoft.Authorization/policyAssignments/read",
  ]

  plan_custom_role_actions = try(
    values.plan_custom_role_actions,
    local.default_plan_custom_role_actions,
  )

  apply_custom_role_actions = try(
    values.apply_custom_role_actions,
    local.default_apply_custom_role_actions,
  )
}

// State units

unit "resource_group" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/state/resource-group?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "state/resource-group"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    name     = local.state_resource_group_name
    location = local.location
  }
}

unit "storage_account" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/state/storage-account?ref=${local.terragrunt_scale_catalog_ref}"

  path = "state/storage-account"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    resource_group_config_path = "../resource-group"

    name     = local.state_storage_account_name
    location = local.location
  }
}

unit "storage_container" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/state/storage-container?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "state/storage-container"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    storage_account_config_path = "../storage-account"

    name = local.state_storage_container_name
  }
}

// OIDC units

// Plan units

unit "plan_app" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-application?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/app"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    display_name = "${local.oidc_resource_prefix}-plan"
    description  = "Entra ID application used by Gruntwork Pipelines for plans"
  }
}

unit "plan_service_principal" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-service-principal?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/service-principal"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    app_config_path = "../app"
  }
}

unit "plan_flexible_federated_identity_credential" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-flexible-federated-identity-credential?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/flexible-federated-identity-credential"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    app_config_path = "../app"

    display_name = "${local.oidc_resource_prefix}-plan"
    description  = "Entra ID flexible federated identity credential used by Gruntwork Pipelines for plans"

    audiences = local.audiences
    issuer    = local.issuer

    claims_matching_expression_value = "claims['sub'] matches 'project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:*'"
  }
}

unit "plan_custom_role_definition" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/custom-role-definition?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/custom-role-definition"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    name        = "${local.oidc_resource_prefix}-plan-custom-role"
    description = "Custom role for Gruntwork Pipelines plan service principal with read-only permissions"

    actions = local.plan_custom_role_actions
  }
}

unit "plan_service_principal_to_plan_custom_role_assignment" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/service-principal-to-sub-role-assignment?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/service-principal-to-plan-custom-role-assignment"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_principal_config_path = "../service-principal"

    role_definition_name = "${local.oidc_resource_prefix}-plan-custom-role"
    description          = "Assign custom plan role to service principal at the subscription scope"
  }
}

unit "plan_service_principal_to_state_contributor_role_assignment" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/service-principal-to-scope-role-assignment?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/service-principal-to-state-contributor-role-assignment"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_principal_config_path = "../service-principal"
    scope_config_path             = "../../../state/storage-account"

    role_definition_name = local.plan_service_principal_to_state_role_definition_assignment
    description          = "Assign Contributor role to service principal at the state scope"
  }
}

// Apply units

unit "apply_app" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-application?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/app"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    display_name = "${local.oidc_resource_prefix}-apply"
    description  = "Entra ID application used by Gruntwork Pipelines for applies and destroys"
  }
}

unit "apply_service_principal" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-service-principal?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/service-principal"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    app_config_path = "../app"
  }
}

unit "apply_federated_identity_credential" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/entra-id-federated-identity-credential?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/federated-identity-credential"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    app_config_path = "../app"

    display_name = "${local.oidc_resource_prefix}-apply"
    description  = "Entra ID federated identity credential used by Gruntwork Pipelines for applies and destroys"

    audiences = local.audiences
    issuer    = local.issuer

    subject = "project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:ref_type:branch:ref:${local.deploy_branch}"
  }
}

unit "apply_custom_role_definition" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/custom-role-definition?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/custom-role-definition"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    name        = "${local.oidc_resource_prefix}-apply-custom-role"
    description = "Custom role for Gruntwork Pipelines apply service principal with deployment permissions"

    actions = local.apply_custom_role_actions
  }
}

unit "apply_service_principal_to_apply_custom_role_assignment" {
  source = "${local.terragrunt_scale_catalog_url}//units/azure/oidc/service-principal-to-sub-role-assignment?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/service-principal-to-apply-custom-role-assignment"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_principal_config_path = "../service-principal"

    role_definition_name = "${local.oidc_resource_prefix}-apply-custom-role"
    description          = "Assign custom apply role to service principal at the subscription scope"
  }
}
