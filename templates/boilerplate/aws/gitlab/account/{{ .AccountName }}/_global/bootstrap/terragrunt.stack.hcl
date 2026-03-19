// Bootstrap stack: provisions the GitLab OIDC provider and plan/apply IAM roles in this environment.
// Terragrunt Stacks: https://docs.terragrunt.com/features/stacks/

locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  account_hcl = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

stack "bootstrap" {
  // To upgrade: update the ?ref= tag and review https://github.com/gruntwork-io/terragrunt-scale-catalog/releases
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/aws/gitlab/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    aws_account_id = "{{ .AWSAccountID }}"

    // Prefix for the IAM roles created: <prefix>-plan and <prefix>-apply.
    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    // Only CI pipelines in this GitLab group/project can assume the IAM roles.
    gitlab_group_name   = "{{ .GitLabGroupName }}"
    gitlab_project_name = "{{ .GitLabProjectName }}"

    {{- if .DeployBranch }}
    deploy_branch = "{{ .DeployBranch }}"
    {{- end }}

    {{- if .Issuer }}
    issuer = "{{ .Issuer }}"
    {{- end }}

    state_bucket_name = local.account_hcl.locals.state_bucket_name
  }
}
