locals {
  // Source resolution
  terragrunt_scale_catalog_url = try(values.terragrunt_scale_catalog_url, "github.com/gruntwork-io/terragrunt-scale-catalog")
  terragrunt_scale_catalog_ref = try(values.terragrunt_scale_catalog_ref, "v1.13.0")

  // AWS account values
  aws_account_id = values.aws_account_id
  aws_partition  = try(values.aws_partition, "aws")

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

  // OIDC condition operator for the apply role. Defaults to "StringEquals" (exact repo+branch match,
  // the secure default). Set to "StringLike" to allow a wildcard sub_apply_value — e.g. trusting many
  // repos under a prefix (repo:org/prefix-*:...) for multi-repo / ephemeral-repo setups. The plan role
  // is always StringLike (any PR ref); this makes the apply role's operator configurable too.
  apply_condition_operator = try(values.apply_condition_operator, "StringEquals")

  state_bucket_name = values.state_bucket_name

  terraform_locks_table_name = try(values.terraform_locks_table_name, "terraform-locks")

  bootstrap_iam_policy_prefix = try(values.bootstrap_iam_policy, "default")

  plan_iam_policy_template_path  = "${get_parent_terragrunt_dir()}/${local.bootstrap_iam_policy_prefix}_plan_iam_policy.json"
  apply_iam_policy_template_path = "${get_parent_terragrunt_dir()}/${local.bootstrap_iam_policy_prefix}_apply_iam_policy.json"

  default_plan_iam_policy = templatefile(local.plan_iam_policy_template_path, {
    state_bucket_name          = local.state_bucket_name
    aws_partition              = local.aws_partition
    terraform_locks_table_name = local.terraform_locks_table_name
  })
  default_apply_iam_policy = templatefile(local.apply_iam_policy_template_path, {
    state_bucket_name          = local.state_bucket_name
    aws_partition              = local.aws_partition
    terraform_locks_table_name = local.terraform_locks_table_name
  })

  plan_iam_policy  = try(values.plan_iam_policy, local.default_plan_iam_policy)
  apply_iam_policy = try(values.apply_iam_policy, local.default_apply_iam_policy)

  oidc_provider_import_arn = try(values.oidc_provider_import_arn, "")

  exclude_oidc_provider = try(values.exclude_oidc_provider, false)

  // The iam-policy module (modules/aws/iam-policy) names each policy "<name>-<sha256(policy)[:8]>" so
  // that a policy-content change produces a NEW policy instead of a 6th version (AWS caps IAM policies
  // at 5 versions). We recompute that exact suffix here — over the same policy JSON passed to the unit
  // (`policy = local.{plan,apply}_iam_policy`) — and append it to the un-hashed import ARNs that arrive
  // from the account template, so the import targets the policy's real, hashed name.
  plan_iam_policy_name_suffix  = substr(sha256(local.plan_iam_policy), 0, 8)
  apply_iam_policy_name_suffix = substr(sha256(local.apply_iam_policy), 0, 8)

  plan_iam_role_import_existing      = try(values.plan_iam_role_import_existing, false)
  raw_plan_iam_policy_import_arn     = try(values.plan_iam_policy_import_arn, "")
  raw_plan_iam_attachment_import_arn = try(values.plan_iam_role_policy_attachment_import_arn, "")
  // Append the content hash so the import ARN matches the hashed policy name. The hash lands on the
  // trailing :policy/<name> segment of both the policy ARN and the "<role>/<policy-arn>" attachment id.
  // Empty stays empty so the unit's `disable = import_arn == ""` still suppresses the import block.
  plan_iam_policy_import_arn                 = local.raw_plan_iam_policy_import_arn == "" ? "" : "${local.raw_plan_iam_policy_import_arn}-${local.plan_iam_policy_name_suffix}"
  plan_iam_role_policy_attachment_import_arn = local.raw_plan_iam_attachment_import_arn == "" ? "" : "${local.raw_plan_iam_attachment_import_arn}-${local.plan_iam_policy_name_suffix}"

  apply_iam_role_import_existing              = try(values.apply_iam_role_import_existing, false)
  raw_apply_iam_policy_import_arn             = try(values.apply_iam_policy_import_arn, "")
  raw_apply_iam_attachment_import_arn         = try(values.apply_iam_role_policy_attachment_import_arn, "")
  apply_iam_policy_import_arn                 = local.raw_apply_iam_policy_import_arn == "" ? "" : "${local.raw_apply_iam_policy_import_arn}-${local.apply_iam_policy_name_suffix}"
  apply_iam_role_policy_attachment_import_arn = local.raw_apply_iam_attachment_import_arn == "" ? "" : "${local.raw_apply_iam_attachment_import_arn}-${local.apply_iam_policy_name_suffix}"

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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_openid_connect_provider_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:oidc-provider/${local.github_token_actions_domain}"

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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_role_name = "${local.oidc_resource_prefix}-plan"
    // Hashed to match the iam-policy module's real name (see plan_iam_policy_name_suffix above).
    mock_iam_policy_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:policy/${local.oidc_resource_prefix}-plan-${local.plan_iam_policy_name_suffix}"

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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_openid_connect_provider_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:oidc-provider/${local.github_token_actions_domain}"

    name = "${local.oidc_resource_prefix}-apply"

    condition_operator = local.apply_condition_operator

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

    // Used to generate accurate mock values; actual values come from dependencies
    mock_iam_role_name = "${local.oidc_resource_prefix}-apply"
    // Hashed to match the iam-policy module's real name (see apply_iam_policy_name_suffix above).
    mock_iam_policy_arn = "arn:${local.aws_partition}:iam::${local.aws_account_id}:policy/${local.oidc_resource_prefix}-apply-${local.apply_iam_policy_name_suffix}"

    import_arn = local.apply_iam_role_policy_attachment_import_arn
  }
}
