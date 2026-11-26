locals {
  // State values
  subscription_id = values.subscription_id

  state_resource_group_name  = values.state_resource_group_name
  state_storage_account_name = values.state_storage_account_name

  state_storage_account_id = "/subscriptions/${local.subscription_id}/resourceGroups/${local.state_resource_group_name}/providers/Microsoft.Storage/storageAccounts/${local.state_storage_account_name}"

  // OIDC values
  oidc_resource_prefix = try(values.oidc_resource_prefix, "pipelines")

  github_token_actions_domain = try(values.github_token_actions_domain, "token.actions.githubusercontent.com")

  github_org_name  = values.github_org_name
  github_repo_name = values.github_repo_name

  // Numeric GitHub org/repo IDs. When both are set, the sub claim is built using GitHub's immutable
  // subject-claim format (repo:org@org_id/repo@repo_id:...) instead of the legacy name-only format.
  // See https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
  github_org_id  = try(values.github_org_id, "")
  github_repo_id = try(values.github_repo_id, "")

  use_immutable_subject = local.github_org_id != "" && local.github_repo_id != ""

  github_org_ref  = local.use_immutable_subject ? "${local.github_org_name}@${local.github_org_id}" : local.github_org_name
  github_repo_ref = local.use_immutable_subject ? "${local.github_repo_name}@${local.github_repo_id}" : local.github_repo_name

  audiences     = try(values.audiences, ["api://AzureADTokenExchange"])
  issuer        = try(values.issuer, "https://${local.github_token_actions_domain}")
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

    // Services teams commonly deploy, comparable to the GCP and AWS defaults.
    "Microsoft.Compute/*",
    "Microsoft.Network/*",
    "Microsoft.ContainerService/*",
    "Microsoft.ContainerRegistry/*",
    "Microsoft.App/*",
    "Microsoft.Web/*",
    "Microsoft.Sql/*",
    "Microsoft.DBforPostgreSQL/*",
    "Microsoft.DBforMySQL/*",
    "Microsoft.DocumentDB/*",
    "Microsoft.Cache/*",
    "Microsoft.KeyVault/*",
    "Microsoft.ServiceBus/*",
    "Microsoft.EventHub/*",
    "Microsoft.ManagedIdentity/*",
    "Microsoft.Insights/*",
    "Microsoft.OperationalInsights/*",

    // Subscription baseline: Defender for Cloud plans and alert contacts, budgets and cost anomaly
    // alerts, and the subscription's own tags. Malware scanning for storage also needs the
    // roleAssignments actions above.
    "Microsoft.Security/pricings/*",
    "Microsoft.Security/securityContacts/*",
    "Microsoft.Security/register/action",
    "Microsoft.Consumption/budgets/*",
    "Microsoft.Consumption/register/action",
    "Microsoft.CostManagement/scheduledActions/*",
    "Microsoft.Resources/tags/*",
  ]

  plan_custom_role_actions = try(
    values.plan_custom_role_actions,
    local.default_plan_custom_role_actions,
  )

  apply_custom_role_actions = try(
    values.apply_custom_role_actions,
    local.default_apply_custom_role_actions,
  )

  // Owners of the plan and apply applications and service principals. An owner can add credentials and
  // sign in as the identity, so the default is none: changes to these units are applied by an
  // administrator, not by Pipelines.
  plan_owners  = try(values.plan_owners, [])
  apply_owners = try(values.apply_owners, [])

  // Optional access to manage a landing zone's management groups and policy. Each grant is made only
  // when its scope is set, so a stack that sets none of these makes no assignments at management-group
  // scope. The scopes must exist before the landing-zone role assignment units apply.
  management_group_scope        = try(values.management_group_scope, "")
  policy_scope                  = try(values.policy_scope, "")
  grantable_role_definition_ids = try(values.grantable_role_definition_ids, [])
  landing_zone_role_assignment_description = try(
    values.landing_zone_role_assignment_description,
    "Gruntwork Pipelines access to manage the landing zone",
  )

  // Limits the apply identity's Role Based Access Control Administrator to assigning and removing the
  // roles in grantable_role_definition_ids.
  grantable_role_definition_id_list = join(", ", local.grantable_role_definition_ids)
  grantable_roles_condition         = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.grantable_role_definition_id_list}})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.grantable_role_definition_id_list}}))"

  plan_landing_zone_role_assignments = merge(
    local.management_group_scope == "" ? null : {
      management_group_reader = {
        scope                = local.management_group_scope
        role_definition_name = "Management Group Reader"
        description          = local.landing_zone_role_assignment_description
      }
    },
    local.policy_scope == "" ? null : {
      policy_reader = {
        scope                = local.policy_scope
        role_definition_name = "Reader"
        description          = local.landing_zone_role_assignment_description
      }
    },
  )

  apply_landing_zone_role_assignments = merge(
    local.management_group_scope == "" ? null : {
      management_group_contributor = {
        scope                = local.management_group_scope
        role_definition_name = "Management Group Contributor"
        description          = local.landing_zone_role_assignment_description
      }
    },
    local.policy_scope == "" ? null : {
      resource_policy_contributor = {
        scope                = local.policy_scope
        role_definition_name = "Resource Policy Contributor"
        description          = local.landing_zone_role_assignment_description
      }
    },
    local.policy_scope == "" || length(local.grantable_role_definition_ids) == 0 ? null : {
      role_based_access_control_administrator = {
        scope                = local.policy_scope
        role_definition_name = "Role Based Access Control Administrator"
        description          = local.landing_zone_role_assignment_description
        condition            = local.grantable_roles_condition
        condition_version    = "2.0"
      }
    },
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

    owners = local.plan_owners
  }
}

unit "plan_service_principal" {
  source = "../../../..//units/azure/oidc/entra-id-service-principal"
  path   = "oidc/plan/service-principal"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"

    owners = local.plan_owners
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

    claims_matching_expression_value = "claims['sub'] matches 'repo:${local.github_org_ref}/${local.github_repo_ref}:*'"
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

unit "plan_service_principal_to_landing_zone_role_assignments" {
  source = "../../../..//units/azure/oidc/service-principal-to-role-assignments"
  path   = "oidc/plan/landing-zone-role-assignments"

  update_source_with_cas = true

  values = {
    service_principal_config_path = "../service-principal"

    role_assignments = local.plan_landing_zone_role_assignments
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

    owners = local.apply_owners
  }
}

unit "apply_service_principal" {
  source = "../../../..//units/azure/oidc/entra-id-service-principal"
  path   = "oidc/apply/service-principal"

  update_source_with_cas = true

  values = {
    app_config_path = "../app"

    owners = local.apply_owners
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

    subject = "repo:${local.github_org_ref}/${local.github_repo_ref}:ref:refs/heads/${local.deploy_branch}"
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

unit "apply_service_principal_to_landing_zone_role_assignments" {
  source = "../../../..//units/azure/oidc/service-principal-to-role-assignments"
  path   = "oidc/apply/landing-zone-role-assignments"

  update_source_with_cas = true

  values = {
    service_principal_config_path = "../service-principal"

    role_assignments = local.apply_landing_zone_role_assignments
  }
}
