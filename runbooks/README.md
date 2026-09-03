# Terragrunt Scale Bootstrap Runbooks

[Gruntwork Runbooks](https://runbooks.gruntwork.io) that guide you through bootstrapping
[Gruntwork Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview) (Terragrunt Scale)
into an `infrastructure-live` repository — interactively, in your browser, with as much automated as
possible.

There is one runbook per **cloud provider × source-control host**:

| | GitHub | GitLab — new repo | GitLab — existing repo |
|---|---|---|---|
| **AWS** | [aws-github](./aws-github) | [aws-gitlab-new-repo](./aws-gitlab-new-repo) | [aws-gitlab-existing-repo](./aws-gitlab-existing-repo) |
| **GCP** | [gcp-github](./gcp-github) | [gcp-gitlab-new-repo](./gcp-gitlab-new-repo) | [gcp-gitlab-existing-repo](./gcp-gitlab-existing-repo) |
| **Azure** | [azure-github](./azure-github) | [azure-gitlab-new-repo](./azure-gitlab-new-repo) | [azure-gitlab-existing-repo](./azure-gitlab-existing-repo) |

The GitHub runbooks handle both repository states in one pass: create the repository on GitHub first
(empty is fine), and the runbook detects from the clone whether it needs to render the full
`infrastructure-live` layout or add another account to a repo that already runs Terragrunt Scale.
The GitLab runbooks are still split, and the *new repo* ones create the project for you.

## Opening a runbook

Install the [Runbooks desktop app](https://runbooks.gruntwork.io/intro/installation/), then open a
runbook locally:

```bash
runbooks open ./runbooks/aws-github
```

…or directly from this repository, without cloning it first:

```bash
runbooks open https://github.com/gruntwork-io/terragrunt-scale-catalog/tree/main/runbooks/aws-github
```

> On a Windows or locked-down machine, toggle **Instruction mode** in the app to get copy-pasteable
> commands you run yourself instead of the app running them for you.

## What each runbook does

Every runbook walks the same arc, specialized per cloud/SCM/repo-state:

1. **Pre-flight checks** — verify `git`, `mise`, the cloud CLI, and the SCM CLI are installed, then
   install `boilerplate`, `terragrunt`, and `opentofu`.
2. **Authenticate** — to the SCM host (GitHub/GitLab) and to the cloud (AWS via the `AwsAuth` block;
   GCP/Azure via `gcloud`/`az` login steps).
3. **Get the repository** — the GitHub runbooks clone the repository you select and read its state from
   the clone; the GitLab *new-repo* runbooks create the project (`glab repo create`) first, and the
   *existing-repo* ones clone yours and check for a `root.hcl`.
4. **Auto-derive identifiers** — see below.
5. **Configure** — a short form collects only the values that genuinely cannot be derived.
6. **Set up the repository** — in the GitHub runbooks this is a single step that renders the matching
   `templates/boilerplate/<cloud>/<scm>/…` template with `boilerplate --non-interactive`, installs the
   tool versions it pins, adds the Pipelines CI workflows, and writes a README. A repo being scaffolded
   gets its CI workflow from the `infrastructure-live` template; a repo that already runs Terragrunt
   Scale has it added without clobbering customizations. The GitLab runbooks still do these as
   separate steps.
7. **Provision** — `terragrunt` plan then apply the bootstrap stack (OIDC trust + state backend).
8. **Open a PR / MR** and run **post-flight checks** that the OIDC resources and generated files exist.

## Automated for you

These runbooks derive everything that can be derived, so you don't type (or mistype) it:

| Value | How it's obtained |
|---|---|
| AWS account ID & partition | `aws sts get-caller-identity` (partition inferred from the ARN) |
| GitHub numeric org & repo IDs | the `org_id` / `repo_id` outputs of the `GitClone` block — used for GitHub's [immutable OIDC subject claims](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/) |
| GCP project number | `gcloud projects describe <project-id>` |
| Azure tenant & subscription IDs | `az account show` |
| Azure plan/apply client IDs | captured from `terragrunt stack output` and written into `.gruntwork/environment-<sub>.hcl` automatically |
| Deploy branch *(GitHub runbooks)* | `git rev-parse --abbrev-ref HEAD` on the clone — the branch you picked when selecting the repository |
| Scaffold vs. add-an-account *(GitHub runbooks)* | presence of a root `root.hcl` in the clone |
| Catalog, Terragrunt, OpenTofu & Terraform versions *(GitHub runbooks)* | the **Resolve the latest versions** step — `git ls-remote` for the catalog, `mise latest` for the tools |

You are only asked for genuine choices: environment/account names, region/location, state bucket or
storage-account names, the OIDC resource prefix, and — in the GitHub runbooks — which IaC binary
Pipelines should use. The GitLab runbooks still ask for the deploy branch.

## Testing

Each runbook ships a `runbook_test.yml` at the **template-validation tier**: it validates that the
runbook parses and its input schema is well-formed, skipping the blocks that require live cloud/SCM
access. Run the full suite with a built `runbooks-cli`:

```bash
runbooks-cli test ./runbooks/...
```

Run a real end-to-end pass manually with cloud + SCM credentials configured. See the
[testing guide](https://runbooks.gruntwork.io/authoring/testing/).

## Maintenance

### How pinned versions stay current

Four fields decide what a bootstrap pins: `TerragruntScaleCatalogRef`, `TerragruntVersion`,
`OpenTofuVersion` and `TerraformVersion`. In the GitHub runbooks all four default to the sentinel
`latest` and are resolved when the runbook runs, by `scripts/resolve-versions.sh`:

- the catalog ref from `git ls-remote --tags --sort=-v:refname`
- the three tool versions from `mise latest <tool>`

`scripts/setup-repository.sh` then applies one rule per field — **your form value if you changed it, else the
newest release, else a built-in pin** — and uses the result for both the `boilerplate` render and the
`mise install` that follows it. Nothing in this repository has to be bumped when Terragrunt or OpenTofu
cuts a release, and an offline run still works off the built-in pins.

### Refreshing the catalog version dropdown

The one thing that *is* baked in is the list of selectable catalog releases. `TerragruntScaleCatalogRef`
is an `enum`, and the Runbooks app reads each `<Inputs>` block's YAML when the runbook is *opened* —
before any step has run — so a script running mid-runbook cannot add to it. After cutting a
`terragrunt-scale-catalog` release, regenerate the list and commit it:

```bash
./runbooks/scripts/update-catalog-refs.sh      # defaults to the 10 newest releases
./runbooks/scripts/update-catalog-refs.sh 20   # or keep more of them selectable
```

A stale list never blocks anyone — `latest` is the first option and the default, and it resolves at run
time. The list only affects which *older* versions can be picked from the dropdown.

### Testing an unreleased catalog

The dropdown can only offer published releases. To run a GitHub runbook against a branch, a tag that
does not exist yet, or a commit SHA, set `TerragruntScaleCatalogRefOverride` in the form's Advanced
section; it wins over the dropdown. A branch is a moving target, so the repository it generates
follows the branch rather than pinning a version — the step says so when the ref does not look like
a release tag.

## Contributing

`aws-github` is the hand-authored reference implementation; the other cells follow its
structure, block-ID conventions, and script style. When adding a runbook, mirror it and keep the
`boilerplate --var` set aligned with the authoritative `templates/boilerplate/**/boilerplate.yml`.
