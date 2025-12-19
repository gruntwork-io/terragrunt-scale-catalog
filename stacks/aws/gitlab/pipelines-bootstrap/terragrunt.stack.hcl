locals {
  // Source resolution
  terragrunt_scale_catalog_url = try(values.terragrunt_scale_catalog_url, "github.com/gruntwork-io/terragrunt-scale-catalog")
  terragrunt_scale_catalog_ref = try(values.terragrunt_scale_catalog_ref, "v1.3.1")

  // AWS account values
  aws_account_id = values.aws_account_id

  // OIDC values
  oidc_resource_prefix = try(values.oidc_resource_prefix, "pipelines")

  gitlab_server_domain = try(values.gitlab_server_domain, "gitlab.com")

  default_issuer = "https://${local.gitlab_server_domain}"

  issuer = try(values.issuer, local.default_issuer)

  gitlab_group_name   = try(values.gitlab_group_name, "")
  gitlab_project_name = try(values.gitlab_project_name, "")

  aud_value = try(values.aud_value, "https://${local.gitlab_server_domain}/${local.gitlab_group_name}")

  default_client_id_list = [
    local.aud_value,
  ]

  client_id_list = try(values.client_id_list, local.default_client_id_list)

  deploy_branch = try(values.deploy_branch, "main")

  sub_key         = try(values.sub_key, "${local.gitlab_server_domain}:sub")
  sub_plan_value  = try(values.sub_plan_value, "project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:*")
  sub_apply_value = try(values.sub_apply_value, "project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:ref_type:branch:ref:${local.deploy_branch}")

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
  }
}

unit "plan_iam_role" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-oidc-role?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/plan/iam-role"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_openid_connect_provider_config_path = "../../oidc-provider"

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_openid_connect_provider_arn = "arn:aws:iam::${local.aws_account_id}:oidc-provider/${local.gitlab_server_domain}"

    name = "${local.oidc_resource_prefix}-plan"

    condition_operator = "StringLike"

    sub_key   = local.sub_key
    sub_value = local.sub_plan_value
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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_role_name   = "${local.oidc_resource_prefix}-plan"
    mock_iam_policy_arn  = "arn:aws:iam::${local.aws_account_id}:policy/${local.oidc_resource_prefix}-plan"
  }
}

unit "apply_iam_role" {
  source = "${local.terragrunt_scale_catalog_url}//units/aws/oidc/iam-oidc-role?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/apply/iam-role"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    iam_openid_connect_provider_config_path = "../../oidc-provider"

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_openid_connect_provider_arn = "arn:aws:iam::${local.aws_account_id}:oidc-provider/${local.gitlab_server_domain}"

    name = "${local.oidc_resource_prefix}-apply"

    sub_key   = local.sub_key
    sub_value = local.sub_apply_value
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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_role_name   = "${local.oidc_resource_prefix}-apply"
    mock_iam_policy_arn  = "arn:aws:iam::${local.aws_account_id}:policy/${local.oidc_resource_prefix}-apply"
  }
}
