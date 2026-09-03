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

## After the bootstrap applies

If you chose to **import** an existing OIDC provider, the generated
`<account>/_global/bootstrap/terragrunt.stack.hcl` keeps an `Import Variables` section naming what
was adopted. Once the apply has succeeded, delete that section and commit.

Leaving it is harmless day to day — an import block whose target is already in state is a no-op, and
the plan stays clean. But it only stays inert while the target exists: if the OIDC provider is later
removed, or the issuer changes, every subsequent plan fails with `Cannot import non-existent remote
object`, including in CI on an unrelated pull request. The generated file carries the same note.

Mirrors the official guides:
[Add Pipelines to a new repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingnewrepo)
and [Add Pipelines to an existing repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingexistingrepo).
