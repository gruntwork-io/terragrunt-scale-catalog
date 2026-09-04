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

## Customising the plan and apply IAM policies

The runbook writes `plan_iam_policy.json` and `apply_iam_policy.json` into
`<account>/_global/bootstrap/`, alongside `terragrunt.stack.hcl`, and points the stack at them:

```hcl
plan_iam_policy  = file("${get_terragrunt_dir()}/plan_iam_policy.json")
apply_iam_policy = file("${get_terragrunt_dir()}/apply_iam_policy.json")
```

They are the catalog's `default_{plan,apply}_iam_policy.json` fetched at the catalog ref this run
pinned, with the partition, state bucket and locks table already substituted — so they are plain IAM
documents, not templates. Edit them, commit, and the next plan picks the change up. Because they are
read with `file()` rather than `templatefile()`, `${aws:...}` IAM policy variables work as written.

Two consequences worth knowing:

- **They pin the policies.** Once these files exist, the catalog's own defaults are never read again.
  Moving the `?ref=` to a newer catalog will not widen or narrow what the roles may do; to pick up
  policy changes from a release, diff your copy against that release's defaults and merge by hand.
- **The bucket name is baked in.** The rest of the stack reads `state_bucket_name` from `account.hcl`
  at run time, but these documents carry the literal name. If the state bucket is ever renamed,
  update the JSON too, or the plan role silently loses access to state and CI fails with
  `AccessDenied` at apply time.

Editing the policies in the catalog's own copy under `.terragrunt-stack/` does not work: Terragrunt
lists those files in `.terragrunt-stack-manifest` and re-copies them on every `stack generate`.

Mirrors the official guides:
[Add Pipelines to a new repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingnewrepo)
and [Add Pipelines to an existing repository](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingexistingrepo).
