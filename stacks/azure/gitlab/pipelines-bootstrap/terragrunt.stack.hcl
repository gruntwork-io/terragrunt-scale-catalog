locals {
  // State values
  subscription_id = values.subscription_id

  state_resource_group_name  = values.state_resource_group_name
  state_storage_account_name = values.state_storage_account_name

  state_storage_account_id = "/subscriptions/${local.subscription_id}/resourceGroups/${local.state_resource_group_name}/providers/Microsoft.Storage/storageAccounts/${local.state_storage_account_name}"

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

// OIDC units

// Plan units

unit "plan_app" {
  source = "../../../..//units/azure/oidc/entra-id-application"
  path   = "oidc/plan/app"

  update_source_with_cas = true

  values = {
    display_name = "${local.oidc_resource_prefix}-plan"
    description  = "Entra ID application used by Gruntwork Pipelines for plans"
  }
}

unit "plan_service_principal" {
  source = "../../../..//units/azure/oidc/entra-id-service-principal"
  path   = "oidc/plan/service-principal"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"
  }
}

unit "plan_flexible_federated_identity_credential" {
  source = "../../../..//units/azure/oidc/entra-id-flexible-federated-identity-credential"
  path   = "oidc/plan/flexible-federated-identity-credential"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"

    display_name = "${local.oidc_resource_prefix}-plan"
    description  = "Entra ID flexible federated identity credential used by Gruntwork Pipelines for plans"

    audiences = local.audiences
    issuer    = local.issuer

    claims_matching_expression_value = "claims['sub'] matches 'project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:*'"
  }
}

unit "plan_custom_role_definition" {
  source = "../../../..//units/azure/oidc/custom-role-definition"
  path   = "oidc/plan/custom-role-definition"

  update_source_with_cas = true

  values = {
    name        = "${local.oidc_resource_prefix}-plan-custom-role"
    description = "Custom role for Gruntwork Pipelines plan service principal with read-only permissions"

    actions = local.plan_custom_role_actions
  }
}

unit "plan_service_principal_to_plan_custom_role_assignment" {
  source = "../../../..//units/azure/oidc/service-principal-to-sub-role-assignment"
  path   = "oidc/plan/service-principal-to-plan-custom-role-assignment"

  update_source_with_cas = true

  values = {
    service_principal_config_path = "../service-principal"

    role_definition_name = "${local.oidc_resource_prefix}-plan-custom-role"
    description          = "Assign custom plan role to service principal at the subscription scope"
  }
}

unit "plan_service_principal_to_state_contributor_role_assignment" {
  source = "../../../..//units/azure/oidc/service-principal-to-scope-role-assignment"
  path   = "oidc/plan/service-principal-to-state-contributor-role-assignment"

  update_source_with_cas = true

  values = {
    service_principal_config_path = "../service-principal"
    scope                         = local.state_storage_account_id

    role_definition_name = local.plan_service_principal_to_state_role_definition_assignment
    description          = "Assign Contributor role to service principal at the state scope"
  }
}

// Apply units

unit "apply_app" {
  source = "../../../..//units/azure/oidc/entra-id-application"
  path   = "oidc/apply/app"

  update_source_with_cas = true

  values = {
    display_name = "${local.oidc_resource_prefix}-apply"
    description  = "Entra ID application used by Gruntwork Pipelines for applies and destroys"
  }
}

unit "apply_service_principal" {
  source = "../../../..//units/azure/oidc/entra-id-service-principal"
  path   = "oidc/apply/service-principal"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"
  }
}

unit "apply_federated_identity_credential" {
  source = "../../../..//units/azure/oidc/entra-id-federated-identity-credential"
  path   = "oidc/apply/federated-identity-credential"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"

    display_name = "${local.oidc_resource_prefix}-apply"
    description  = "Entra ID federated identity credential used by Gruntwork Pipelines for applies and destroys"

    audiences = local.audiences
    issuer    = local.issuer

    subject = "project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:ref_type:branch:ref:${local.deploy_branch}"
  }
}

unit "apply_custom_role_definition" {
  source = "../../../..//units/azure/oidc/custom-role-definition"
  path   = "oidc/apply/custom-role-definition"

  update_source_with_cas = true

  values = {
    name        = "${local.oidc_resource_prefix}-apply-custom-role"
    description = "Custom role for Gruntwork Pipelines apply service principal with deployment permissions"

    actions = local.apply_custom_role_actions
  }
}

unit "apply_service_principal_to_apply_custom_role_assignment" {
  source = "../../../..//units/azure/oidc/service-principal-to-sub-role-assignment"
  path   = "oidc/apply/service-principal-to-apply-custom-role-assignment"

  update_source_with_cas = true

  values = {
    service_principal_config_path = "../service-principal"

    role_definition_name = "${local.oidc_resource_prefix}-apply-custom-role"
    description          = "Assign custom apply role to service principal at the subscription scope"
  }
}
