# Azure + GitHub Actions: Subscription Bootstrap Template

Boilerplate template that scaffolds the subscription-level bootstrap configuration for Terragrunt Scale on Azure with GitHub Actions.

Rendering this template produces a `{{ .SubscriptionName }}/bootstrap/` directory containing a `terragrunt.stack.hcl` that references the [`stacks/azure/github/pipelines-bootstrap`](../../../../stacks/azure/github/pipelines-bootstrap) stack. Applying that stack provisions the Entra ID application, service principal, federated identity credentials, and role assignments that GitHub Actions workflows use to authenticate to Azure.

This template is typically pulled in as a dependency of the sibling [`infrastructure-live`](../infrastructure-live) template, but it can also be rendered on its own to add another subscription to an existing Terragrunt Scale repository.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/github/subscription?ref=main' \
  --output-folder ./infrastructure-live \
  --var SubscriptionName=prod \
  --var GitHubOrgName=acme \
  --var GitHubRepoName=infrastructure-live \
  --var AzureLocation=eastus
```

## Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SubscriptionName` | yes | | Name of the Azure subscription being bootstrapped. |
| `GitHubOrgName` | yes | | GitHub organization that owns the repository. |
| `GitHubRepoName` | yes | | Repository name; only workflows in this repo may authenticate. |
| `AzureLocation` | yes | | Azure region for the subscription's state-backend resources. |
| `DeployBranch` | no | `main` | Branch granted the apply role. |
| `TerragruntScaleCatalogRef` | no | `v1.13.0` | Git ref of this catalog to pin the stack source to. |
| `OIDCResourcePrefix` | no | `pipelines` | Prefix applied to the Entra ID resources. |
| `Issuer` | no | computed | Override for the OIDC issuer URL. |
| `CloudEnvironment` | no | `public` | Azure cloud to target. Set to `usgovernment` for Azure Government, or `china` / `german` / `stack` for other sovereign clouds. Threaded into both the Pipelines HCL (`cloud_environment`) and the generated `azurerm` / `azuread` provider blocks. See the [Connecting to Azure Government](https://docs.gruntwork.io/2.0/docs/pipelines/tutorials/deploying-to-azure-government) tutorial. |

## How It Works

- `boilerplate.yml` declares the variables above and a dependency on [`.dependencies/azure/subscription`](../../../.dependencies/azure/subscription), which contributes `sub.hcl` and the `.gruntwork/environment-<sub>.hcl` file the rendered stack reads.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
