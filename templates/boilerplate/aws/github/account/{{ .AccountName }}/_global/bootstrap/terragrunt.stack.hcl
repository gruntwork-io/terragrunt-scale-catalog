locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  account_hcl = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

stack "bootstrap" {
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/aws/github/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    terragrunt_scale_catalog_ref = "{{ .TerragruntScaleCatalogRef }}"

    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    github_org_name  = "{{ .GitHubOrgName }}"
    github_repo_name = "{{ .GitHubRepoName }}"

    {{- if .Issuer }}
    issuer = "{{ .Issuer }}"
    {{- end }}

    state_bucket_name = local.account_hcl.locals.state_bucket_name

    {{- if .OIDCProviderImportARN }}
    oidc_provider_import_arn = "{{ .OIDCProviderImportARN }}"
    {{- end}}

    {{- if .PlanIAMRoleImportExisting }}
    plan_iam_role_import_existing = {{ .PlanIAMRoleImportExisting }}
    {{- end }}

    {{- if .PlanIAMPolicyImportARN }}
    plan_iam_policy_import_arn = "{{ .PlanIAMPolicyImportARN }}"
    {{- end }}

    {{- if .PlanIAMRolePolicyAttachmentImportARN }}
    plan_iam_role_policy_attachment_import_arn = "{{ .PlanIAMRolePolicyAttachmentImportARN }}"
    {{- end }}

    {{- if .ApplyIAMRoleImportExisting }}
    apply_iam_role_import_existing = {{ .ApplyIAMRoleImportExisting }}
    {{- end }}

    {{- if .ApplyIAMPolicyImportARN }}
    apply_iam_policy_import_arn = "{{ .ApplyIAMPolicyImportARN }}"
    {{- end }}

    {{- if .ApplyIAMRolePolicyAttachmentImportARN }}
    apply_iam_role_policy_attachment_import_arn = "{{ .ApplyIAMRolePolicyAttachmentImportARN }}"
    {{- end }}
  }
}
