# Terragrunt Scale Bootstrap Runbooks

[Gruntwork Runbooks](https://runbooks.gruntwork.io) that guide you through bootstrapping
[Gruntwork Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview) (Terragrunt Scale)
into an `infrastructure-live` repository — interactively, in your browser, with as much automated as
possible.

There is one runbook for every combination of **cloud provider × source-control host × repository state**:

| | GitHub — new repo | GitHub — existing repo | GitLab — new repo | GitLab — existing repo |
|---|---|---|---|---|
| **AWS** | [aws-github-new-repo](./aws-github-new-repo) | [aws-github-existing-repo](./aws-github-existing-repo) | [aws-gitlab-new-repo](./aws-gitlab-new-repo) | [aws-gitlab-existing-repo](./aws-gitlab-existing-repo) |
| **GCP** | [gcp-github-new-repo](./gcp-github-new-repo) | [gcp-github-existing-repo](./gcp-github-existing-repo) | [gcp-gitlab-new-repo](./gcp-gitlab-new-repo) | [gcp-gitlab-existing-repo](./gcp-gitlab-existing-repo) |
| **Azure** | [azure-github-new-repo](./azure-github-new-repo) | [azure-github-existing-repo](./azure-github-existing-repo) | [azure-gitlab-new-repo](./azure-gitlab-new-repo) | [azure-gitlab-existing-repo](./azure-gitlab-existing-repo) |

## Opening a runbook

Install the [Runbooks desktop app](https://runbooks.gruntwork.io/intro/installation/), then open a
runbook locally:

```bash
runbooks open ./runbooks/aws-github-existing-repo
```

…or directly from this repository, without cloning it first:

```bash
runbooks open https://github.com/gruntwork-io/terragrunt-scale-catalog/tree/main/runbooks/aws-github-existing-repo
```

> On a Windows or locked-down machine, toggle **Instruction mode** in the app to get copy-pasteable
> commands you run yourself instead of the app running them for you.

## What each runbook does

Every runbook walks the same arc, specialized per cloud/SCM/repo-state:

1. **Pre-flight checks** — verify `git`, `mise`, the cloud CLI, and the SCM CLI are installed, then
   install `boilerplate`, `terragrunt`, and `opentofu`.
2. **Authenticate** — to the SCM host (GitHub/GitLab) and to the cloud (AWS via the `AwsAuth` block;
   GCP/Azure via `gcloud`/`az` login steps).
3. **Get the repository** — *new-repo* runbooks create the repo (`gh`/`glab repo create`) and clone it;
   *existing-repo* runbooks clone your repo and check for a `root.hcl`.
4. **Auto-derive identifiers** — see below.
5. **Configure** — a short form collects only the values that genuinely cannot be derived.
6. **Generate** — render the matching `templates/boilerplate/<cloud>/<scm>/…` template into the repo with
   `boilerplate --non-interactive`.
7. **Provision** — `terragrunt` plan then apply the bootstrap stack (OIDC trust + state backend).
8. **Wire up CI** — *new-repo* runbooks get the CI workflow from the `infrastructure-live` template;
   *existing-repo* runbooks add it explicitly.
9. **Open a PR / MR** and run **post-flight checks** that the OIDC resources and generated files exist.

## Automated for you

These runbooks derive everything that can be derived, so you don't type (or mistype) it:

| Value | How it's obtained |
|---|---|
| AWS account ID & partition | `aws sts get-caller-identity` (partition inferred from the ARN) |
| GitHub numeric org & repo IDs | `gh api repos/{owner}/{repo}` — used for GitHub's [immutable OIDC subject claims](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/) |
| GCP project number | `gcloud projects describe <project-id>` |
| Azure tenant & subscription IDs | `az account show` |
| Azure plan/apply client IDs | captured from `terragrunt stack output` and written into `.gruntwork/environment-<sub>.hcl` automatically |

You are only asked for genuine choices: environment/account names, region/location, state bucket or
storage-account names, the OIDC resource prefix, and the deploy branch.

## Testing

Each runbook ships a `runbook_test.yml` at the **template-validation tier**: it validates that the
runbook parses and its input schema is well-formed, skipping the blocks that require live cloud/SCM
access. Run the full suite with a built `runbooks-cli`:

```bash
runbooks-cli test ./runbooks/...
```

Run a real end-to-end pass manually with cloud + SCM credentials configured. See the
[testing guide](https://runbooks.gruntwork.io/authoring/testing/).

## Contributing

`aws-github-existing-repo` is the hand-authored reference implementation; the other cells follow its
structure, block-ID conventions, and script style. When adding a runbook, mirror it and keep the
`boilerplate --var` set aligned with the authoritative `templates/boilerplate/**/boilerplate.yml`.
