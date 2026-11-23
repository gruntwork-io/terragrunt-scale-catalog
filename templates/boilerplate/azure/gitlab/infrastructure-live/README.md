# Azure + GitLab CI: Infrastructure-Live Template

Boilerplate template that scaffolds a complete Terragrunt Scale repository for Azure with GitLab CI.

Rendering this template produces the full repository layout: a root `root.hcl`, the `.gruntwork/` metadata directory, a `.gitlab-ci.yml` pipeline, a `.mise.toml`, a `.gitignore`, and the first subscription's pipelines-identity stack.

## Usage

```bash
boilerplate \
  --template-url 'github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/gitlab/infrastructure-live?ref=main' \
  --output-folder ./infrastructure-live \
  --var SubscriptionName=prod \
  --var GitLabGroupName=acme \
  --var GitLabProjectName=infrastructure-live \
  --var AzureLocation=eastus
```

All variables accepted by the [`subscription`](../subscription) template are accepted here too, since this template depends on it.

## Composed Dependencies

This template renders by combining these dependency templates, in order:

1. [`.dependencies/common`](../../../.dependencies/common) — `.gruntwork/repository.hcl`, `.mise.toml`, `.gitignore`.
2. [`.dependencies/gitlab`](../../../.dependencies/gitlab) — `.gitlab-ci.yml`.
3. [`.dependencies/azure/base`](../../../.dependencies/azure/base) — root `root.hcl` configuring the Azure remote state backend. This layer deliberately comes after `common` because it overrides a subset of `common`'s files.
4. [`../subscription`](../subscription) — the subscription-level pipelines-identity stack for `{{ .SubscriptionName }}`.

After rendering, commit the output, then `cd` into `{{ .SubscriptionName }}/pipelines-identity` and run `terragrunt stack run apply` to provision the OIDC infrastructure.

Pipelines does not plan or apply the `pipelines-identity` stacks: the rendered `.gruntwork/repository.hcl` lists `*/pipelines-identity/**` in `ignore_list`. Apply them yourself as a Global Administrator, both the first time and after any change, so the plan identity never needs Microsoft Graph read access. `ignore_list` as a list needs Pipelines v4.29.0 or later.

## How It Works

- `boilerplate.yml` declares the dependency chain above. All variables are inherited from the dependencies.
- `skip_files` excludes this README from the rendered output so the scaffolded repository does not inherit catalog-internal documentation.
