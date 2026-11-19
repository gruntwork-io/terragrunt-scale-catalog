# GCP + GitLab CI: Infrastructure-Live Template

Boilerplate template that scaffolds a complete Terragrunt Scale repository for GCP with GitLab CI.

Rendering this template produces the full repository layout: a root `root.hcl`, the `.gruntwork/` metadata directory, a GitLab CI pipeline (`.gitlab-ci.yml`) with support for plan/apply, drift detection (optional), and unlock, a `.mise.toml`, a `.gitignore`, and the first project's pipelines-identity stack.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/gitlab/infrastructure-live?ref=main' \
  --output-folder ./infrastructure-live \
  --var ProjectName=prod \
  --var GCPProjectID=my-project-123 \
  --var GCPProjectNumber=123456789012 \
  --var GitLabGroupName=acme \
  --var GitLabProjectName=infrastructure-live \
  --var GCPRegion=us-central1 \
  --var StateBucketName=my-project-tfstate
```

Boilerplate will prompt for any variable not supplied on the command line.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `IncludeDriftDetection` | `true` | When `false`, removes drift-detection from the pipeline options. |

All variables accepted by the [`project`](../project) template (e.g. `ProjectName`, `GCPProjectID`, `GCPProjectNumber`, `GitLabGroupName`, `GitLabProjectName`, `GCPRegion`, `StateBucketName`, and the Workload Identity overrides) are accepted here too, since this template depends on it.

## Composed Dependencies

This template is a thin composition layer. It renders by combining these dependency templates, in order:

1. [`.dependencies/common`](../../../.dependencies/common) — `.gruntwork/repository.hcl`, `.mise.toml`, `.gitignore`.
2. [`.dependencies/gitlab`](../../../.dependencies/gitlab) — `.gitlab-ci.yml` pipeline.
3. [`.dependencies/gcp/base`](../../../.dependencies/gcp/base) — root `root.hcl` configuring the GCS remote state backend and Google provider. This layer deliberately comes after `common` because it overrides a subset of `common`'s files.
4. [`../project`](../project) — the project-level pipelines-identity stack for `{{ .ProjectName }}`.

After rendering, commit the output, then `cd` into `{{ .ProjectName }}/pipelines-identity` and run `terragrunt stack run apply` to provision the Workload Identity infrastructure.

## How It Works

- `boilerplate.yml` declares the dependency chain above.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
