#!/bin/bash
# Write a README.md describing the repository this runbook just configured — but only if the
# repository has none. An existing README is never touched: it is the repository's own front door,
# and whatever is in it was put there deliberately.
#
# The content is assembled with a literal heredoc plus placeholder substitution rather than an
# expanding one, because the text is full of markdown backticks and ${...} examples that a shell
# would otherwise try to execute or expand.
set -euo pipefail

rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

# A README that is still the stub GitHub creates with a new repository — a heading, maybe a one-line
# description, nothing else — carries no information worth keeping, and leaving it in place means the
# repository is left undocumented. Anything with real structure (sections, code, lists, links, tables)
# is somebody's work and is never touched.
readme_is_stub() {
  local f=$1 body
  # Any structural markdown means it is a real README.
  if grep -qE '^(##|```|[-*+] |[0-9]+\. |\||>)' "$f" || grep -q 'http' "$f"; then
    return 1
  fi
  body=$(grep -vE '^[[:space:]]*$' "$f" | wc -l | tr -d ' ')
  # A heading plus at most a couple of lines of blurb.
  [ "$body" -le 3 ] || return 1
  head -1 "$f" | grep -qE '^#[[:space:]]' || return 1
  return 0
}

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_StateStorageAccountName=$(rb_unquote "{{ .inputs.StateStorageAccountName }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  exit 1
fi

cd "$REPO_FILES"

TARGET="README.md"
if [ -f README.md ]; then
  if readme_is_stub README.md; then
    log_warn "README.md is still the stub created with the repository; replacing it."
    log_warn "Replacing this content:"
    while IFS= read -r line; do log_warn "    ${line}"; done < README.md
    TITLE=$(head -1 README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
  else
    # A README with real content belongs to whoever wrote it. Write the generated one alongside it
    # instead, so nothing is lost and the choice of whether to adopt it stays with the reader.
    TARGET="README.template.md"
    TITLE=$(grep -m1 -E '^#[[:space:]]' README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    log_info "README.md already exists and has real content; leaving it untouched."
    log_info "Writing the generated documentation to README.template.md instead."
  fi
fi
[ -n "${TITLE:-}" ] || TITLE="infrastructure-live"

TOOL="opentofu"
if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
  recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
  [ -n "$recorded" ] && TOOL="$recorded"
fi

cat > "$TARGET" <<'READMEEOF'
# __RB_TITLE__

Infrastructure [repo](https://docs.terragrunt.com/guides/ci-with-terragrunt/terragrunt-scale/#repository-structure) for this organization, managed with [Terragrunt Scale](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview) and deployed by [Gruntwork Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview).

Changes are made by pull request. Opening one runs `terragrunt plan`; merging to `__RB_BRANCH__`
runs `terragrunt apply`. Nothing is applied from a laptop in normal operation.

## Repository layout

```
root.hcl
.mise.toml
.gitignore
.gruntwork/
  repository.hcl
  environment-__RB_SUB__.hcl
.github/workflows/
  pipelines.yml
  pipelines-unlock.yml
  pipelines-drift-detection.yml
__RB_SUB__/
  sub.hcl
  bootstrap/
    terragrunt.stack.hcl
```

| Path | What it is |
| --- | --- |
| `root.hcl` | Root Terragrunt config: azurerm remote state, the azurerm/azuread providers, shared inputs |
| `.mise.toml` | Pinned tool versions (Terragrunt, __RB_TOOL__, Azure CLI, Python) |
| `.gruntwork/repository.hcl` | Repository-wide Pipelines settings: deploy branch, `tf_binary` |
| `.gruntwork/environment-__RB_SUB__.hcl` | Which subscription this environment deploys into, and the client IDs Pipelines authenticates as |
| `.github/workflows/pipelines.yml` | Plan on pull requests, apply on merge to `__RB_BRANCH__` |
| `.github/workflows/pipelines-unlock.yml` | Manually release a stuck state lock |
| `.github/workflows/pipelines-drift-detection.yml` | Scheduled drift detection, if enabled |
| `__RB_SUB__/sub.hcl` | Subscription-level values: subscription and tenant ids, state storage |
| `__RB_SUB__/bootstrap/` | The bootstrap stack (see below) |

Each additional subscription is another top-level directory with the same shape, plus its own
`.gruntwork/environment-<name>.hcl`.

## How the pieces fit

**`root.hcl`** is included by every unit. It configures the azurerm backend — one state blob per unit,
keyed by its path — and generates the `azurerm` and `azuread` providers. Change it only when something
applies to the whole repository.

Note that the `remote_state` block starts commented out. The first bootstrap apply has to run against
local state, because the Storage Account holding the state does not exist yet. Once it does, the block
is uncommented and the state migrated into it — the runbook does both.

**`.gruntwork/repository.hcl`** is Pipelines' repository-wide configuration: the deploy branch, and
`tf_binary` (this repository uses **__RB_TOOL__**). `.gruntwork/environment-<name>.hcl` maps an
environment to its subscription and records the plan/apply client IDs.

**The bootstrap stack** (`__RB_SUB__/bootstrap/terragrunt.stack.hcl`) provisions what Pipelines needs
before it can deploy anything into the subscription:

- an Entra ID application and service principal for `terragrunt plan` (read-only, used on pull requests),
- an Entra ID application and service principal for `terragrunt apply` (used on merges to the deploy branch),
- federated identity credentials binding each application to this repository's GitHub OIDC tokens,
- the resource group, Storage Account `__RB_STORAGE__` and container that hold OpenTofu state.

Federated credentials mean no client secrets: GitHub's OIDC token is exchanged for an Entra ID token
at run time.

It is applied once, when the subscription is onboarded. After that it is ordinary configuration:
changes to it go through the same plan/apply flow as anything else.

**The workflows** call Gruntwork's reusable workflow rather than containing the logic themselves, so
upgrading Pipelines is a version bump in `.github/workflows/pipelines.yml`.

**`.mise.toml`** pins the tool versions. CI installs exactly these, so a local run matches CI. Run
`mise install` once after cloning.

## Working in this repository

```bash
mise install                    # install the pinned tool versions
az login
cd __RB_SUB__/bootstrap
terragrunt run --all plan       # see what would change
```

Open a pull request with your change and let Pipelines plan it. Read the plan in the PR comment
before merging — merging is what applies it.

## Adding another subscription

Re-run the Gruntwork Runbook that created this repository and give it a new subscription name. It adds
a new top-level directory and a new `.gruntwork/environment-<name>.hcl`, and leaves everything here
untouched.

## Reference

- [Pipelines overview](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview)
- [Configuration as code reference](https://docs.gruntwork.io/2.0/reference/pipelines/configurations-as-code/api)
- [Terragrunt documentation](https://terragrunt.gruntwork.io)
READMEEOF

sed -i.bak \
  -e "s|__RB_TITLE__|${TITLE}|g" \
  -e "s|__RB_SUB__|${RB_SubscriptionName}|g" \
  -e "s|__RB_BRANCH__|${RB_DeployBranch}|g" \
  -e "s|__RB_PREFIX__|${RB_OIDCResourcePrefix}|g" \
  -e "s|__RB_STORAGE__|${RB_StateStorageAccountName}|g" \
  -e "s|__RB_TOOL__|${TOOL}|g" "$TARGET"
rm -f "$TARGET.bak"


if [ "$TARGET" = "README.template.md" ]; then
  # Say what this file is, at the top, so nobody has to guess where it came from.
  tmp=$(mktemp)
  {
    printf '%s\n' "<!--"
    printf '%s\n' "  Generated by the Gruntwork Runbook that set up this repository."
    printf '%s\n' ""
    printf '%s\n' "  Your repository already had a README, so this was written alongside it rather than over it."
    printf '%s\n' "  Adopt it with:  mv README.template.md README.md"
    printf '%s\n' "  Or take the parts you want and delete the rest — nothing depends on this file."
    printf '%s\n' "-->"
    printf '%s\n' ""
    cat "$TARGET"
  } > "$tmp" && mv "$tmp" "$TARGET"
  log_info "Wrote README.template.md alongside your README.md. Review it, then rename it over README.md"
  log_info "if you want it, or delete it — nothing depends on it."
  exit 0
fi

log_info "Wrote README.md describing the repository layout, bootstrap stack, workflows and Pipelines config."
exit 0
