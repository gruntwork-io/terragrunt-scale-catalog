# infrastructure-live-no-cloud

Auth-less Pipelines bootstrap used by the Terragrunt Scale **"Run your first pipeline"** onboarding
wizard. It is the no-cloud sibling of [`../infrastructure-live`](../infrastructure-live).

## What it renders

- `.github/workflows/` — the standard Pipelines workflows (from `.dependencies/github`).
- `.gruntwork/repository.hcl` — repository-level Pipelines config (from `.dependencies/common`).
- `.gruntwork/environment-<AccountName>.hcl` — a Pipelines environment with an **empty**
  `authentication {}` block (from `.dependencies/aws/account-no-cloud`).

It deliberately does **not** render the S3 remote-state root (`root.hcl`), `account.hcl`/`region.hcl`,
or the pipelines-identity stack (OIDC provider + plan/apply IAM roles) — all of which require cloud credentials
the customer has not yet provided.

## Why

The onboarding goal is to let a customer reach a working `plan`/`apply` (the "wow moment") **before**
authorizing their cloud. The tutorial unit dropped on top of this skeleton is a self-contained
`null_resource` with local state and no provider, so it plans/applies with zero cloud credentials.

Once the customer authorizes their cloud in the **"Connect to your cloud"** wizard, the sibling
[`../cloud-config`](../cloud-config) template is layered on top to add the S3 state backend, the
pipelines-identity stack, and the real `authentication { aws_oidc { ... } }` config.

## Variables

| Variable | Description | Default |
|---|---|---|
| `AccountName` | Pipelines environment name for the tutorial pass (e.g. `pipelines-tutorial`); units live under `<AccountName>/`. | — |
| `IncludeDriftDetection` | Include the drift-detection workflow. | `true` |
| `DeployBranch`, `TerragruntVersion`, `OpenTofuVersion`, `NewCommentPerPush`, `PipelinesWorkflowsRef` | Inherited from the `common` / `github` dependencies. | see those templates |
