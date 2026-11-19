# AWS + GitLab CI: Infrastructure-Live Template

Boilerplate template that scaffolds a complete Terragrunt Scale repository for AWS with GitLab CI.

Rendering this template produces the full repository layout: a root `root.hcl`, the `.gruntwork/` metadata directory, a `.gitlab-ci.yml` pipeline, a `.mise.toml`, a `.gitignore`, and the first account's pipelines-identity stack.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/gitlab/infrastructure-live?ref=main' \
  --output-folder ./infrastructure-live \
  --var AccountName=prod \
  --var GitLabGroupName=acme \
  --var GitLabProjectName=infrastructure-live
```

All variables accepted by the [`account`](../account) template are accepted here too, since this template depends on it.

## Composed Dependencies

This template renders by combining these dependency templates, in order:

1. [`.dependencies/common`](../../../.dependencies/common) — `.gruntwork/repository.hcl`, `.mise.toml`, `.gitignore`.
2. [`.dependencies/gitlab`](../../../.dependencies/gitlab) — `.gitlab-ci.yml`.
3. [`.dependencies/aws/base`](../../../.dependencies/aws/base) — root `root.hcl` configuring the AWS remote state backend.
4. [`../account`](../account) — the account-level pipelines-identity stack for `{{ .AccountName }}`.

After rendering, commit the output, then `cd` into `{{ .AccountName }}/_global/pipelines-identity` and run `terragrunt stack run apply` to provision the OIDC infrastructure.

## How It Works

- `boilerplate.yml` declares the dependency chain above. All variables are inherited from the dependencies.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
