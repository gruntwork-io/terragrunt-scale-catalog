# GCP + GitHub Actions: Project Bootstrap Template

Boilerplate template that scaffolds the project-level bootstrap configuration for Terragrunt Scale on GCP with GitHub Actions.

Rendering this template produces a `{{ .ProjectName }}/bootstrap/` directory containing a `terragrunt.stack.hcl` that references the [`stacks/gcp/github/pipelines-bootstrap`](../../../../stacks/gcp/github/pipelines-bootstrap) stack. Applying that stack provisions a Workload Identity Pool, Workload Identity Pool Provider, and the `plan`/`apply` service accounts with IAM bindings that GitHub Actions workflows use to authenticate to GCP.

This template is typically pulled in as a dependency of the sibling [`infrastructure-live`](../infrastructure-live) template, but it can also be rendered on its own to add another project to an existing Terragrunt Scale repository.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/github/project?ref=main' \
  --output-folder ./infrastructure-live \
  --var ProjectName=prod \
  --var GCPProjectID=my-project-123 \
  --var GCPProjectNumber=123456789012 \
  --var GitHubOrgName=acme \
  --var GitHubRepoName=infrastructure-live \
  --var GCPRegion=us-central1 \
  --var StateBucketName=my-project-tfstate
```

## Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ProjectName` | yes | | Human-readable name of the GCP project being bootstrapped; used as a folder name. |
| `GCPProjectID` | yes | | GCP project ID (string identifier) of the project being bootstrapped. |
| `GCPProjectNumber` | yes | | GCP project number (numeric ID) of the project being bootstrapped. |
| `GitHubOrgName` | yes | | GitHub organization that owns the repository. |
| `GitHubRepoName` | yes | | Repository name; only workflows in this repo may authenticate. |
| `GCPRegion` | yes | | GCP region used to configure the Google provider and GCS state backend. |
| `StateBucketName` | yes | | Name of the GCS bucket used for storing OpenTofu state. Must be globally unique. Also used to grant the plan service account `roles/storage.objectUser` scoped to this bucket for state locking. |
| `DeployBranch` | no | `main` | Branch granted the apply service account binding. |
| `TerragruntScaleCatalogRef` | no | `v1.13.0` | Git ref of this catalog to pin the stack source to. |
| `OIDCResourcePrefix` | no | `pipelines` | Prefix applied to Workload Identity Pool and service account resources. |
| `Issuer` | no | computed | Override for the OIDC issuer URL; defaults to `https://token.actions.githubusercontent.com`. |
| `WorkloadIdentityPoolID` | no | computed | ID of the Workload Identity Pool; computed from `OIDCResourcePrefix` if not specified. |
| `WorkloadIdentityPoolProviderID` | no | computed | ID of the Workload Identity Pool Provider; computed from `OIDCResourcePrefix` if not specified. |
| `PlanRoles` | no | `[]` | Additional project-level IAM roles granted to the plan service account. The bucket-scoped custom role for state locking is always granted on `StateBucketName` regardless of this value. |
| `ApplyRoles` | no | `[]` | IAM roles granted to the apply service account. |
| `WorkloadIdentityPoolImportExisting` | no | `false` | Import an existing Workload Identity Pool instead of creating one. |
| `WorkloadIdentityPoolProviderImportExisting` | no | `false` | Import an existing Workload Identity Pool Provider instead of creating one. |
| `PlanServiceAccountImportExisting` | no | `false` | Import an existing plan service account instead of creating one. |
| `PlanWorkloadIdentityBindingImportExisting` | no | `false` | Import an existing plan SA Workload Identity IAM binding instead of creating one. |
| `PlanStateBucketCustomRoleImportExisting` | no | `false` | Import an existing plan state bucket custom IAM role instead of creating one. |
| `PlanProjectIAMBindingsImportExisting` | no | `false` | Import existing plan SA project IAM role bindings instead of creating them. |
| `PlanStateBucketIAMBindingImportExisting` | no | `false` | Import an existing plan SA state bucket IAM binding instead of creating one. |
| `ApplyServiceAccountImportExisting` | no | `false` | Import an existing apply service account instead of creating one. |
| `ApplyWorkloadIdentityBindingImportExisting` | no | `false` | Import an existing apply SA Workload Identity IAM binding instead of creating one. |
| `ApplyProjectIAMBindingsImportExisting` | no | `false` | Import existing apply SA project IAM role bindings instead of creating them. |

## How It Works

- `boilerplate.yml` declares the variables above and a dependency on [`.dependencies/gcp/project`](../../../.dependencies/gcp/project), which contributes the `project.hcl` and `.gruntwork/environment-<project>.hcl` files the rendered stack reads.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
