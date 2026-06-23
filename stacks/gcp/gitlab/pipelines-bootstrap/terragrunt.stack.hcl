locals {
  // Source resolution
  terragrunt_scale_catalog_url = try(values.terragrunt_scale_catalog_url, "github.com/gruntwork-io/terragrunt-scale-catalog")
  terragrunt_scale_catalog_ref = try(values.terragrunt_scale_catalog_ref, "v1.13.0")

  // Project values
  project_id     = values.project_id
  project_number = values.project_number

  // OIDC values
  oidc_resource_prefix = try(values.oidc_resource_prefix, "pipelines")

  gitlab_server_domain = try(values.gitlab_server_domain, "gitlab.com")

  gitlab_group_name   = values.gitlab_group_name
  gitlab_project_name = values.gitlab_project_name

  default_issuer = "https://${local.gitlab_server_domain}"
  issuer         = try(values.issuer, local.default_issuer)
  deploy_branch  = try(values.deploy_branch, "main")

  // Workload Identity Pool settings
  workload_identity_pool_id          = try(values.workload_identity_pool_id, "${local.oidc_resource_prefix}-pool")
  workload_identity_pool_provider_id = try(values.workload_identity_pool_provider_id, "${local.oidc_resource_prefix}-provider")

  // Attribute mapping for GitLab CI OIDC tokens
  default_attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.project_path"   = "assertion.project_path"
    "attribute.ref"            = "assertion.ref"
    "attribute.ref_type"       = "assertion.ref_type"
    "attribute.namespace_path" = "assertion.namespace_path"
  }

  attribute_mapping = try(values.attribute_mapping, local.default_attribute_mapping)

  // Attribute condition to restrict which identities can authenticate
  attribute_condition = try(values.attribute_condition, "assertion.project_path == '${local.gitlab_group_name}/${local.gitlab_project_name}'")

  // Default IAM roles for plan (read-only)
  default_plan_roles = [
    "roles/viewer",
    "roles/storage.objectViewer",
  ]

  // Default IAM roles for apply (read-write)
  default_apply_roles = [
    "roles/compute.admin",
    "roles/container.admin",
    "roles/cloudsql.admin",
    "roles/iam.roleAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
    "roles/compute.networkAdmin",
    "roles/run.admin",
    "roles/pubsub.admin",
    "roles/dns.admin",
    "roles/secretmanager.admin",
    "roles/bigquery.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageAdmin",
  ]

  plan_roles  = try(values.plan_roles, local.default_plan_roles)
  apply_roles = try(values.apply_roles, local.default_apply_roles)

  state_bucket_name = try(values.state_bucket_name, null)

  workload_identity_pool_import_existing          = try(values.workload_identity_pool_import_existing, false)
  workload_identity_pool_provider_import_existing = try(values.workload_identity_pool_provider_import_existing, false)

  plan_service_account_import_existing            = try(values.plan_service_account_import_existing, false)
  plan_workload_identity_binding_import_existing  = try(values.plan_workload_identity_binding_import_existing, false)
  plan_project_iam_bindings_import_existing       = try(values.plan_project_iam_bindings_import_existing, false)
  plan_state_bucket_custom_role_import_existing   = try(values.plan_state_bucket_custom_role_import_existing, false)
  plan_state_bucket_iam_binding_import_existing   = try(values.plan_state_bucket_iam_binding_import_existing, false)
  apply_service_account_import_existing           = try(values.apply_service_account_import_existing, false)
  apply_workload_identity_binding_import_existing = try(values.apply_workload_identity_binding_import_existing, false)
  apply_project_iam_bindings_import_existing      = try(values.apply_project_iam_bindings_import_existing, false)

  // Custom role ID for plan SA state bucket access (hyphens replaced to satisfy GCP role_id constraints)
  state_bucket_custom_role_id = replace("${local.oidc_resource_prefix}_state_bucket", "-", "_")

  // Workload Identity principal formats
  // For plan: allow any pipeline run from the project (principalSet with attribute filter)
  plan_member = "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${local.workload_identity_pool_id}/attribute.project_path/${local.gitlab_group_name}/${local.gitlab_project_name}"

  // For apply: restrict to specific branch (principal with subject)
  apply_member = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${local.workload_identity_pool_id}/subject/project_path:${local.gitlab_group_name}/${local.gitlab_project_name}:ref_type:branch:ref:${local.deploy_branch}"
}

// Workload Identity Pool (shared by plan and apply)
unit "workload_identity_pool" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/workload-identity-pool?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/workload-identity-pool"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    project_id                = local.project_id
    workload_identity_pool_id = local.workload_identity_pool_id
    display_name              = "GitLab CI Pool"
    description               = "Workload Identity Pool for GitLab CI OIDC authentication"

    import_existing = local.workload_identity_pool_import_existing
  }
}

// Workload Identity Pool Provider
unit "workload_identity_pool_provider" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/workload-identity-pool-provider?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/workload-identity-pool-provider"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    workload_identity_pool_config_path = "../workload-identity-pool"

    project_id                         = local.project_id
    workload_identity_pool_provider_id = local.workload_identity_pool_provider_id
    display_name                       = "GitLab CI Provider"
    description                        = "OIDC provider for GitLab CI"

    issuer_uri          = local.issuer
    attribute_mapping   = local.attribute_mapping
    attribute_condition = local.attribute_condition
    allowed_audiences   = try(values.allowed_audiences, ["https://${local.gitlab_server_domain}/${local.gitlab_group_name}"])

    import_existing = local.workload_identity_pool_provider_import_existing
  }
}

// Plan Service Account
unit "plan_service_account" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/service-account?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/plan/service-account"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    project_id   = local.project_id
    account_id   = "${local.oidc_resource_prefix}-plan"
    display_name = "Pipelines Plan Service Account"
    description  = "Service account used by Gruntwork Pipelines for plans"

    import_existing = local.plan_service_account_import_existing
  }
}

// Plan Service Account Workload Identity Binding (allows any pipeline run from the project)
unit "plan_workload_identity_binding" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/service-account-iam-binding?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/plan/workload-identity-binding"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_account_config_path = "../service-account"

    member = local.plan_member

    import_existing = local.plan_workload_identity_binding_import_existing
  }
}

// Plan IAM Role Bindings
unit "plan_project_iam_bindings" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/project-iam-member?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/plan/project-iam-bindings"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_account_config_path = "../service-account"

    project_id = local.project_id
    roles      = local.plan_roles

    import_existing = local.plan_project_iam_bindings_import_existing
  }
}

// Plan State Bucket Custom Role (bucket-scoped, only when state_bucket_name is provided)
// Combines storage.objectUser permissions with storage.buckets.getIamPolicy for least-privilege plan access
unit "plan_state_bucket_custom_role" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/custom-role?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/plan/state-bucket-custom-role"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    project_id  = local.project_id
    role_id     = local.state_bucket_custom_role_id
    title       = "Pipelines Plan State Bucket Role"
    description = "Least-privilege role for plan SA: state locking (storage.objectUser) and bucket IAM policy reads (storage.buckets.getIamPolicy)"
    permissions = [
      "storage.objects.create",
      "storage.objects.delete",
      "storage.objects.get",
      "storage.objects.list",
      "storage.objects.update",
      "storage.buckets.getIamPolicy",
    ]

    import_existing = local.plan_state_bucket_custom_role_import_existing
  }
}

// Plan State Bucket IAM Binding (bucket-scoped, only when state_bucket_name is provided)
unit "plan_state_bucket_iam_binding" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/storage-bucket-custom-role-iam-member?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/plan/state-bucket-iam-binding"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_account_config_path = "../service-account"
    custom_role_config_path     = "../state-bucket-custom-role"

    bucket = local.state_bucket_name

    import_existing = local.plan_state_bucket_iam_binding_import_existing
  }
}

// Apply Service Account
unit "apply_service_account" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/service-account?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/apply/service-account"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    project_id   = local.project_id
    account_id   = "${local.oidc_resource_prefix}-apply"
    display_name = "Pipelines Apply Service Account"
    description  = "Service account used by Gruntwork Pipelines for applies and destroys"

    import_existing = local.apply_service_account_import_existing
  }
}

// Apply Service Account Workload Identity Binding (restricted to deploy branch)
unit "apply_workload_identity_binding" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/service-account-iam-binding?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/apply/workload-identity-binding"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_account_config_path = "../service-account"

    member = local.apply_member

    import_existing = local.apply_workload_identity_binding_import_existing
  }
}

// Apply IAM Role Bindings
unit "apply_project_iam_bindings" {
  source = "${local.terragrunt_scale_catalog_url}//units/gcp/oidc/project-iam-member?ref=${local.terragrunt_scale_catalog_ref}"
  path   = "oidc/gitlab/apply/project-iam-bindings"

  values = {
    base_url = local.terragrunt_scale_catalog_url
    ref      = local.terragrunt_scale_catalog_ref

    service_account_config_path = "../service-account"

    project_id = local.project_id
    roles      = local.apply_roles

    import_existing = local.apply_project_iam_bindings_import_existing
  }
}
