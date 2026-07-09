locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  project_hcl = read_terragrunt_config(find_in_parent_folders("project.hcl"))
}

stack "bootstrap" {
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/gcp/github/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    terragrunt_scale_catalog_ref = "{{ .TerragruntScaleCatalogRef }}"

    project_id     = "{{ .GCPProjectID }}"
    project_number = "{{ .GCPProjectNumber }}"

    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    github_org_name  = "{{ .GitHubOrgName }}"
    github_repo_name = "{{ .GitHubRepoName }}"

    {{- if and .GitHubOrgID .GitHubRepoID }}
    // Numeric GitHub org/repo IDs: switches the apply role's sub claim to GitHub's immutable subject-claim format.
    github_org_id  = "{{ .GitHubOrgID }}"
    github_repo_id = "{{ .GitHubRepoID }}"
    {{- end }}

    {{- if .Issuer }}
    issuer = "{{ .Issuer }}"
    {{- end }}

    {{- if .DeployBranch }}
    deploy_branch = "{{ .DeployBranch }}"
    {{- end }}

    {{- if .WorkloadIdentityPoolID }}
    workload_identity_pool_id = "{{ .WorkloadIdentityPoolID }}"
    {{- end }}

    {{- if .WorkloadIdentityPoolProviderID }}
    workload_identity_pool_provider_id = "{{ .WorkloadIdentityPoolProviderID }}"
    {{- end }}

    state_bucket_name = "{{ .StateBucketName }}"

    {{- if .PlanRoles }}
    plan_roles = {{ toJson .PlanRoles }}
    {{- end }}

    {{- if .ApplyRoles }}
    apply_roles = {{ toJson .ApplyRoles }}
    {{- end }}

    // =========================================================================
    // Import Variables
    //
    // The following variables are used to import existing GCP resources into
    // OpenTofu/Terraform state. Once the stack has been applied and resources
    // have been successfully imported, it is safe to remove this entire section.
    // =========================================================================
    {{- if .WorkloadIdentityPoolImportExisting }}
    workload_identity_pool_import_existing = true
    {{- end }}

    {{- if .WorkloadIdentityPoolProviderImportExisting }}
    workload_identity_pool_provider_import_existing = true
    {{- end }}

    {{- if .PlanServiceAccountImportExisting }}
    plan_service_account_import_existing = true
    {{- end }}

    {{- if .PlanWorkloadIdentityBindingImportExisting }}
    plan_workload_identity_binding_import_existing = true
    {{- end }}

    {{- if .PlanStateBucketCustomRoleImportExisting }}
    plan_state_bucket_custom_role_import_existing = true
    {{- end }}

    {{- if .ApplyServiceAccountImportExisting }}
    apply_service_account_import_existing = true
    {{- end }}

    {{- if .ApplyWorkloadIdentityBindingImportExisting }}
    apply_workload_identity_binding_import_existing = true
    {{- end }}

    {{- if .PlanProjectIAMBindingsImportExisting }}
    plan_project_iam_bindings_import_existing = true
    {{- end }}

    {{- if .ApplyProjectIAMBindingsImportExisting }}
    apply_project_iam_bindings_import_existing = true
    {{- end }}

    {{- if .PlanStateBucketIAMBindingImportExisting }}
    plan_state_bucket_iam_binding_import_existing = true
    {{- end }}
    // =========================================================================
    // End Import Variables
    // =========================================================================
  }
}
