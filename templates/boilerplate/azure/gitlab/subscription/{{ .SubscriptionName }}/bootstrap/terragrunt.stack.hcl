locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))
}

stack "bootstrap" {
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/azure/gitlab/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    gitlab_group_name   = "{{ .GitLabGroupName }}"
    gitlab_project_name = "{{ .GitLabProjectName }}"

    {{- if .DeployBranch }}
    deploy_branch = "{{ .DeployBranch }}"
    {{- end }}

    {{- if .Issuer }}
    issuer = "{{ .Issuer }}"
    {{- end }}

    location = "{{ .AzureLocation }}"

    state_resource_group_name    = local.sub_hcl.locals.state_resource_group_name
    state_storage_account_name   = local.sub_hcl.locals.state_storage_account_name
    state_storage_container_name = local.sub_hcl.locals.state_storage_container_name
  }
}

