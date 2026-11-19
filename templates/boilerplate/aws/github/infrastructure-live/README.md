# AWS + GitHub Actions: Infrastructure-Live Template

Boilerplate template that scaffolds a complete Terragrunt Scale repository for AWS with GitHub Actions.

Rendering this template produces the full repository layout: a root `root.hcl`, the `.gruntwork/` metadata directory, GitHub Actions workflows for plan/apply and (optionally) drift detection, a `.mise.toml`, a `.gitignore`, and the first account's pipelines-identity stack.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/github/infrastructure-live?ref=main' \
  --output-folder ./infrastructure-live \
  --var AccountName=prod \
  --var AWSAccountID=111122223333 \
  --var GitHubOrgName=acme \
  --var GitHubRepoName=infrastructure-live
```

Boilerplate will prompt for any variable not supplied on the command line.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `IncludeDriftDetection` | `true` | When `false`, skips rendering the drift-detection workflow. |

All variables accepted by the [`account`](../account) template (e.g. `AccountName`, `AWSAccountID`, `GitHubOrgName`, `GitHubRepoName`, the `*ImportExisting` flags) are accepted here too, since this template depends on it.

## Composed Dependencies

This template is a thin composition layer. It renders by combining these dependency templates, in order:

1. [`.dependencies/common`](../../../.dependencies/common) — `.gruntwork/repository.hcl`, `.mise.toml`, `.gitignore`.
2. [`.dependencies/github`](../../../.dependencies/github) — `pipelines.yml` and `pipelines-unlock.yml` workflows.
3. [`.dependencies/github-drift-detection`](../../../.dependencies/github-drift-detection) — drift-detection workflow, skipped when `IncludeDriftDetection` is `false`.
4. [`.dependencies/aws/base`](../../../.dependencies/aws/base) — root `root.hcl` configuring the AWS remote state backend.
5. [`../account`](../account) — the account-level pipelines-identity stack for `{{ .AccountName }}`.

After rendering, commit the output, then `cd` into `{{ .AccountName }}/_global/pipelines-identity` and run `terragrunt stack run apply` to provision the OIDC infrastructure.

## How It Works

- `boilerplate.yml` declares `IncludeDriftDetection` and the dependency chain above.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
