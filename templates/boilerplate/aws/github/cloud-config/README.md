# cloud-config

The cloud-authorization layer for the Terragrunt Scale **"Connect to your cloud"** onboarding wizard.
It is applied **on top of** a repo that was already bootstrapped with the auth-less
[`../infrastructure-live-no-cloud`](../infrastructure-live-no-cloud) template.

## What it renders (additively)

- `root.hcl` — S3 remote-state backend + AWS provider generation (from `.dependencies/aws/base`).
- `<AccountName>/account.hcl`, `<AccountName>/_global/region.hcl` — state bucket + region config.
- `<AccountName>/_global/pipelines-identity/terragrunt.stack.hcl` — the pipelines-identity stack that provisions the
  GitHub OIDC provider and the plan/apply IAM roles.
- `.gruntwork/environment-<AccountName>.hcl` — a real Pipelines environment with
  `authentication { aws_oidc { ... } }` pointing at the bootstrapped roles.

It does **not** re-render the Pipelines workflows or `repository.hcl`; those already exist from the
no-cloud bootstrap.

## Why a separate template

The onboarding flow defers all cloud-credentialed setup until the customer authorizes their cloud, so
they can reach a working `plan`/`apply` first. `infrastructure-live-no-cloud` ships the auth-less
skeleton; this template fills in the S3 state, the pipelines-identity stack, and the real OIDC auth once cloud
access is available. Keeping them as two templates avoids conditional rendering inside a single
template and keeps the existing [`../infrastructure-live`](../infrastructure-live) untouched.

## Variables

Inherited from the `account` dependency chain — see
[`../account/boilerplate.yml`](../account/boilerplate.yml) and
[`../../../.dependencies/aws/account/boilerplate.yml`](../../../.dependencies/aws/account/boilerplate.yml):
`AccountName`, `AWSAccountID`, `AWSRegion`, `StateBucketName`, `OIDCResourcePrefix`, `Partition`,
`GitHubOrgName`, `GitHubRepoName`, `DeployBranch`, `TerragruntScaleCatalogRef`, and the
`*ImportExisting` flags.
