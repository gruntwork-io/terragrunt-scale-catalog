// Bootstrap stack: provisions plan/apply App Registrations (Federated Identity) and Azure Blob state storage.
// Terragrunt Stacks: https://docs.terragrunt.com/features/stacks/

locals {
  // Read from parent configurations instead of defining these values locally
  // so that other stacks and units in this directory can reuse the same configurations.
  sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))
}

stack "bootstrap" {
  // To upgrade: update the ?ref= tag and review https://github.com/gruntwork-io/terragrunt-scale-catalog/releases
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/azure/github/pipelines-bootstrap?ref={{ .TerragruntScaleCatalogRef }}"
  path   = "bootstrap"

  values = {
    // Prefix for the App Registrations created: <prefix>-plan and <prefix>-apply.
    oidc_resource_prefix = "{{ .OIDCResourcePrefix }}"

    // Only Actions workflows in this org/repo can authenticate via the App Registrations.
    github_org_name  = "{{ .GitHubOrgName }}"
    github_repo_name = "{{ .GitHubRepoName }}"

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
