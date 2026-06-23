# AWS + GitLab CI: Account Bootstrap Template

Boilerplate template that scaffolds the account-level bootstrap configuration for Terragrunt Scale on AWS with GitLab CI.

Rendering this template produces a `{{ .AccountName }}/_global/bootstrap/` directory containing a `terragrunt.stack.hcl` that references the [`stacks/aws/gitlab/pipelines-bootstrap`](../../../../stacks/aws/gitlab/pipelines-bootstrap) stack. Applying that stack provisions an OIDC provider and the `plan`/`apply` IAM roles that GitLab CI jobs assume.

This template is typically pulled in as a dependency of the sibling [`infrastructure-live`](../infrastructure-live) template, but it can also be rendered on its own to add another account to an existing Terragrunt Scale repository.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/gitlab/account?ref=main' \
  --output-folder ./infrastructure-live \
  --var AccountName=prod \
  --var GitLabGroupName=acme \
  --var GitLabProjectName=infrastructure-live
```

## Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `AccountName` | yes | | Name of the AWS account being bootstrapped. |
| `GitLabGroupName` | yes | | GitLab group that owns the project. |
| `GitLabProjectName` | yes | | Project name; only CI jobs in this project may assume the IAM roles. |
| `DeployBranch` | no | `main` | Branch granted the apply role. |
| `TerragruntScaleCatalogRef` | no | `v1.13.0` | Git ref of this catalog to pin the stack source to. |
| `OIDCResourcePrefix` | no | `pipelines` | Prefix for the IAM role names. |
| `Issuer` | no | computed | Override for the OIDC issuer URL (useful for self-hosted GitLab). |

## How It Works

- `boilerplate.yml` declares the variables above and a dependency on [`.dependencies/aws/account`](../../../.dependencies/aws/account), which contributes `account.hcl` and the `.gruntwork/environment-<account>.hcl` file the rendered stack reads.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
