# GCP + GitHub Actions: Infrastructure-Live Template

Boilerplate template that scaffolds a complete Terragrunt Scale repository for GCP with GitHub Actions.

Rendering this template produces the full repository layout: a root `root.hcl`, the `.gruntwork/` metadata directory, GitHub Actions workflows for plan/apply and (optionally) drift detection, a `.mise.toml`, a `.gitignore`, and the first project's pipelines-identity stack.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/github/infrastructure-live?ref=main' \
  --output-folder ./infrastructure-live \
  --var ProjectName=prod \
  --var GCPProjectID=my-project-123 \
  --var GCPProjectNumber=123456789012 \
  --var GitHubOrgName=acme \
  --var GitHubRepoName=infrastructure-live \
  --var GCPRegion=us-central1 \
  --var StateBucketName=my-project-tfstate
```

Boilerplate will prompt for any variable not supplied on the command line.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `IncludeDriftDetection` | `true` | When `false`, skips rendering the drift-detection workflow. |

All variables accepted by the [`project`](../project) template (e.g. `ProjectName`, `GCPProjectID`, `GCPProjectNumber`, `GitHubOrgName`, `GitHubRepoName`, `GCPRegion`, `StateBucketName`, and the Workload Identity overrides) are accepted here too, since this template depends on it.

## Composed Dependencies

This template is a thin composition layer. It renders by combining these dependency templates, in order:

1. [`.dependencies/common`](../../../.dependencies/common) — `.gruntwork/repository.hcl`, `.mise.toml`, `.gitignore`.
2. [`.dependencies/github`](../../../.dependencies/github) — `pipelines.yml` and `pipelines-unlock.yml` workflows.
3. [`.dependencies/github-drift-detection`](../../../.dependencies/github-drift-detection) — drift-detection workflow, skipped when `IncludeDriftDetection` is `false`.
4. [`.dependencies/gcp/base`](../../../.dependencies/gcp/base) — root `root.hcl` configuring the GCS remote state backend and Google provider. This layer deliberately comes after `common` because it overrides a subset of `common`'s files.
5. [`../project`](../project) — the project-level pipelines-identity stack for `{{ .ProjectName }}`.

After rendering, commit the output, then `cd` into `{{ .ProjectName }}/pipelines-identity` and run `terragrunt stack run apply` to provision the Workload Identity infrastructure.

## How It Works

- `boilerplate.yml` declares the dependency chain above.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
