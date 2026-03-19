// Bootstrap stack: provisions the GitHub OIDC provider and plan/apply IAM roles in this environment.
// Terragrunt Stacks: https://docs.terragrunt.com/features/stacks/

locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  account_hcl = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

stack "bootstrap" {
  // To upgrade: update the ?ref= tag and review https://github.com/gruntwork-io/terragrunt-scale-catalog/releases
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/aws/github/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    // Should match the ?ref= above.
    terragrunt_scale_catalog_ref = "{{ .TerragruntScaleCatalogRef }}"

    aws_account_id = "{{ .AWSAccountID }}"

    // Prefix for the IAM roles created: <prefix>-plan and <prefix>-apply.
    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    // Only Actions workflows in this org/repo can assume the IAM roles.
    github_org_name  = "{{ .GitHubOrgName }}"
    github_repo_name = "{{ .GitHubRepoName }}"

    {{- if .DeployBranch }}
    deploy_branch = "{{ .DeployBranch }}"
    {{- end }}

    {{- if .Issuer }}
    issuer = "{{ .Issuer }}"
    {{- end }}

    {{- if .AdditionalAudiences }}
    additional_audiences = {{ toJson .AdditionalAudiences }}
    {{- end }}

    {{- if .ExcludeOIDCProvider }}
    exclude_oidc_provider = true
    {{- end }}

    state_bucket_name = local.account_hcl.locals.state_bucket_name

    {{- if .OIDCProviderTags }}
    oidc_provider_tags = {{ toJson .OIDCProviderTags }}
    {{- end }}



    // =========================================================================
    // Import Variables
    //
    // The following variables are used to import existing AWS resources into
    // OpenTofu/Terraform state. Once the stack has been applied and resources
    // have been successfully imported, it is safe to remove this entire section.
    // =========================================================================
    {{- if .OIDCProviderImportExisting }}
    oidc_provider_import_arn = "arn:aws:iam::{{ .AWSAccountID }}:oidc-provider/
      {{- if .Issuer -}}
        {{ trimPrefix .Issuer "https://" }}
      {{- else -}}
        token.actions.githubusercontent.com
      {{- end -}}
    "
    {{- end }}

    {{- if .PlanIAMRoleImportExisting }}
    plan_iam_role_import_existing = true
    {{- end }}

    {{- if .PlanIamPolicyImportExisting }}
    plan_iam_policy_import_arn = "arn:aws:iam::{{ .AWSAccountID }}:policy/{{ .OIDCResourcePrefix }}-plan"
    {{- end }}

    {{- if .PlanIAMRolePolicyAttachmentImportExisting }}
    plan_iam_role_policy_attachment_import_arn = "{{ .OIDCResourcePrefix }}-plan/arn:aws:iam::{{ .AWSAccountID }}:policy/{{ .OIDCResourcePrefix }}-plan"
    {{- end }}

    {{- if .ApplyIAMRoleImportExisting }}
    apply_iam_role_import_existing = true
    {{- end }}

    {{- if .ApplyIamPolicyImportExisting }}
    apply_iam_policy_import_arn = "arn:aws:iam::{{ .AWSAccountID }}:policy/{{ .OIDCResourcePrefix }}-apply"
    {{- end }}

    {{- if .ApplyIAMRolePolicyAttachmentImportExisting }}
    apply_iam_role_policy_attachment_import_arn = "{{ .OIDCResourcePrefix }}-apply/arn:aws:iam::{{ .AWSAccountID }}:policy/{{ .OIDCResourcePrefix }}-apply"
    {{- end }}
    // =========================================================================
    // End Import Variables
    // =========================================================================

  }
}
