# AWS + GitHub Actions: Account Bootstrap Template

Boilerplate template that scaffolds the account-level bootstrap configuration for Terragrunt Scale on AWS with GitHub Actions.

Rendering this template produces a `{{ .AccountName }}/_global/bootstrap/` directory containing a `terragrunt.stack.hcl` that references the [`stacks/aws/github/pipelines-bootstrap`](../../../../stacks/aws/github/pipelines-bootstrap) stack. Applying that stack provisions an OIDC provider and the `plan`/`apply` IAM roles that GitHub Actions workflows assume.

This template is typically pulled in as a dependency of the sibling [`infrastructure-live`](../infrastructure-live) template, but it can also be rendered on its own to add another account to an existing Terragrunt Scale repository.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/github/account?ref=main' \
  --output-folder ./infrastructure-live \
  --var AccountName=prod \
  --var AWSAccountID=111122223333 \
  --var GitHubOrgName=acme \
  --var GitHubRepoName=infrastructure-live
```

## Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `AccountName` | yes | | Name of the AWS account being bootstrapped. Used as the top-level directory name. |
| `AWSAccountID` | yes | | 12-digit AWS account ID. |
| `GitHubOrgName` | yes | | GitHub organization that owns the repository. |
| `GitHubRepoName` | yes | | Repository name; only workflows in this repo may assume the IAM roles. |
| `DeployBranch` | no | `main` | Branch granted the apply role. |
| `TerragruntScaleCatalogRef` | no | `v1.13.0` | Git ref of this catalog to pin the stack source to. |
| `OIDCResourcePrefix` | no | `pipelines` | Prefix for the IAM role names (`<prefix>-plan`, `<prefix>-apply`). |
| `Issuer` | no | computed | Override for the OIDC issuer URL. |
| `AdditionalAudiences` | no | `[]` | Extra audiences appended to `sts.amazonaws.com`. |
| `ExcludeOIDCProvider` | no | `false` | Skip provisioning the OIDC provider (reuse an existing one in the account). |

### Importing Existing Resources

If the account already contains IAM resources with the same names, set the matching `*ImportExisting` variables to `true` so the generated stack imports them rather than failing on create. Remove the import block from the rendered `terragrunt.stack.hcl` after the first apply.

| Variable | Imports |
| --- | --- |
| `OIDCProviderImportExisting` | OIDC provider |
| `OIDCProviderTags` | Tags to set on an imported provider |
| `PlanIAMRoleImportExisting` | `<prefix>-plan` role |
| `PlanIamPolicyImportExisting` | `<prefix>-plan` policy |
| `PlanIAMRolePolicyAttachmentImportExisting` | plan role-policy attachment |
| `ApplyIAMRoleImportExisting` | `<prefix>-apply` role |
| `ApplyIamPolicyImportExisting` | `<prefix>-apply` policy |
| `ApplyIAMRolePolicyAttachmentImportExisting` | apply role-policy attachment |

## How It Works

- `boilerplate.yml` declares the variables above and a dependency on [`.dependencies/aws/account`](../../../.dependencies/aws/account), which contributes the `account.hcl` and `.gruntwork/environment-<account>.hcl` files the rendered stack reads.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
