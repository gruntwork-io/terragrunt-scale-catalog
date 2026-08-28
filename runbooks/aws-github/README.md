# Bootstrap Gruntwork Pipelines — AWS + GitHub

A [Gruntwork Runbook](https://runbooks.gruntwork.io) that installs Gruntwork Pipelines (Terragrunt Scale)
into a GitHub `infrastructure-live` repository and bootstraps one **AWS** account.

It handles both starting points, detected from the repository after it is cloned:

- **no `root.hcl`** — renders the full repository layout (root config, `.mise.toml`, CI workflows,
  and the first account's bootstrap stack);
- **`root.hcl` present** — adds only the new account's directory and bootstrap stack.

Create the repository on GitHub first (tick *Add a README file*) — this runbook selects it, it does not
create it.

Open it with:

```bash
runbooks open ./runbooks/aws-github
```

Or directly from the catalog:

```bash
runbooks open https://github.com/gruntwork-io/terragrunt-scale-catalog/tree/main/runbooks/aws-github
```

Mirrors the official guides:
[Add Pipelines to a new repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingnewrepo)
and [Add Pipelines to an existing repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingexistingrepo).
