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

    {{- if .AdditionalAudiences }}
    additional_audiences = {{ toJson .AdditionalAudiences }}
    {{- end }}

    {{- if .ExcludeOIDCProvider }}
    exclude_oidc_provider = true
    {{- end }}

    state_bucket_name = local.account_hcl.locals.state_bucket_name

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

    {{- if .OIDCProviderTags }}
    oidc_provider_tags = {{ toJson .OIDCProviderTags }}
    {{- end }}
  }
}
