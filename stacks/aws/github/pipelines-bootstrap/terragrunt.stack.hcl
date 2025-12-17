locals {
  // Source resolution
  terragrunt_scale_catalog_url = try(values.terragrunt_scale_catalog_url, "github.com/gruntwork-io/terragrunt-scale-catalog")
  terragrunt_scale_catalog_ref = try(values.terragrunt_scale_catalog_ref, "v1.3.1")

  // OIDC values
  oidc_resource_prefix = try(values.oidc_resource_prefix, "pipelines")

  github_token_actions_domain = try(values.github_token_actions_domain, "token.actions.githubusercontent.com")

  github_server_domain = try(values.github_server_domain, "github.com")

  default_issuer = "https://${local.github_token_actions_domain}"

  issuer = try(values.issuer, local.default_issuer)

  github_org_name  = try(values.github_org_name, "")
  github_repo_name = try(values.github_repo_name, "")

  aud_value = try(values.aud_value, "sts.amazonaws.com")

  additional_audiences = try(values.additional_audiences, [])

  default_client_id_list = concat(
    [local.aud_value],
    local.additional_audiences,
  )

  client_id_list = try(values.client_id_list, local.default_client_id_list)

  deploy_branch = try(values.deploy_branch, "main")

  sub_key         = try(values.sub_key, "${local.github_token_actions_domain}:sub")
  sub_plan_value  = try(values.sub_plan_value, "repo:${local.github_org_name}/${local.github_repo_name}:*")
  sub_apply_value = try(values.sub_apply_value, "repo:${local.github_org_name}/${local.github_repo_name}:ref:refs/heads/${local.deploy_branch}")

  state_bucket_name = values.state_bucket_name

  bootstrap_iam_policy_prefix = try(values.bootstrap_iam_policy, "default")

  plan_iam_policy_template_path  = "${get_parent_terragrunt_dir()}/${local.bootstrap_iam_policy_prefix}_plan_iam_policy.json"
  apply_iam_policy_template_path = "${get_parent_terragrunt_dir()}/${local.bootstrap_iam_policy_prefix}_apply_iam_policy.json"

  default_plan_iam_policy = templatefile(local.plan_iam_policy_template_path, {
    state_bucket_name = local.state_bucket_name
  })
  default_apply_iam_policy = templatefile(local.apply_iam_policy_template_path, {
    state_bucket_name = local.state_bucket_name
  })

  plan_iam_policy  = try(values.plan_iam_policy, local.default_plan_iam_policy)
  apply_iam_policy = try(values.apply_iam_policy, local.default_apply_iam_policy)

  oidc_provider_import_arn = try(values.oidc_provider_import_arn, "")

  exclude_oidc_provider = try(values.exclude_oidc_provider, false)

  plan_iam_role_import_existing = try(values.plan_iam_role_import_existing, false)
  plan_iam_policy_import_arn = try(values.plan_iam_policy_import_arn, "")
  plan_iam_role_policy_attachment_import_arn = try(values.plan_iam_role_policy_attachment_import_arn, "")

  apply_iam_role_import_existing = try(values.apply_iam_role_import_existing, false)
  apply_iam_policy_import_arn = try(values.apply_iam_policy_import_arn, "")
  apply_iam_role_policy_attachment_import_arn = try(values.apply_iam_role_policy_attachment_import_arn, "")

  oidc_provider_tags = try(values.oidc_provider_tags, {})
}

// State units

unit "oidc_provider" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-openid-connect-provider?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/oidc-provider"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    url = local.issuer

    client_id_list = local.client_id_list

    import_arn = local.oidc_provider_import_arn

    tags = local.oidc_provider_tags

    exclude_if     = local.exclude_oidc_provider
    exclude_no_run = local.exclude_oidc_provider
  }
}

unit "plan_iam_role" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-oidc-role?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/iam-role"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_openid_connect_provider_config_path = "../../oidc-provider"

    name = "${local.oidc_resource_prefix}-plan"

    condition_operator = "StringLike"

    sub_key   = local.sub_key
    sub_value = local.sub_plan_value

    import_existing = local.plan_iam_role_import_existing
  }
}

unit "plan_iam_policy" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-policy?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/iam-policy"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    name = "${local.oidc_resource_prefix}-plan"

    policy = local.plan_iam_policy

    import_arn = local.plan_iam_policy_import_arn
  }
}

unit "plan_iam_role_policy_attachment" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-role-policy-attachment?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/iam-role-policy-attachment"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_role_config_path   = "../iam-role"
    iam_policy_config_path = "../iam-policy"

    import_arn = local.plan_iam_role_policy_attachment_import_arn
  }
}

unit "apply_iam_role" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-oidc-role?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/iam-role"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_openid_connect_provider_config_path = "../../oidc-provider"

    name = "${local.oidc_resource_prefix}-apply"

    sub_key   = local.sub_key
    sub_value = local.sub_apply_value

    import_existing = local.apply_iam_role_import_existing
  }
}

unit "apply_iam_policy" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-policy?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/iam-policy"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_role_config_path = "../iam-role"

    name = "${local.oidc_resource_prefix}-apply"

    policy = local.apply_iam_policy

    import_arn = local.apply_iam_policy_import_arn
  }
}

unit "apply_iam_role_policy_attachment" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-role-policy-attachment?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/iam-role-policy-attachment"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_role_config_path   = "../iam-role"
    iam_policy_config_path = "../iam-policy"

    import_arn = local.apply_iam_role_policy_attachment_import_arn
  }
}
