#!/bin/bash
# Inspect the repository once, before anything is generated, and answer both questions the rest of
# the runbook depends on:
#
#   1. Is it on the deploy branch? The setup pull request opens against the branch this clone is on,
#      while Pipelines records the deploy branch separately. If they disagree the request targets the
#      wrong branch and Pipelines never runs for it — visible only after the request is opened.
#   2. Which layout is it? A root `root.hcl` means an existing Terragrunt Scale repository, so only
#      the new account is added. No root.hcl means the full repository layout is rendered into it.
#
# Publishes repo_mode for the generate, workflow, README and verification steps. Nothing downstream
# can run until this passes, which is deliberate: both answers gate what those steps do.
set -uo pipefail

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

RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")

if [ -z "$RB_DeployBranch" ]; then
  log_error "DeployBranch is empty. Fill in the deploy branch form above."
  exit 1
fi

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  log_error "If the repository has no commits yet, use the clone block's **Create default branch**"
  log_error "button — the clone holds back its outputs until the branch exists."
  exit 1
fi

cd "$REPO_FILES"

# --- 1. branch ---------------------------------------------------------------
CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')

if [ -z "$CURRENT" ] || [ "$CURRENT" = "HEAD" ]; then
  log_error "Could not determine the current branch of ${REPO_FILES}."
  log_error "A detached HEAD or a repository with no commits cannot be used; check out [${RB_DeployBranch}] and re-run."
  exit 1
fi

if [ "$CURRENT" != "$RB_DeployBranch" ]; then
  log_error "Branch mismatch: the repository is on [${CURRENT}] but the deploy branch is [${RB_DeployBranch}]."
  log_error "The setup pull request would open against [${CURRENT}], so Pipelines would never run for it."
  log_error "Fix either side, then run this check again:"
  log_error "  - check out [${RB_DeployBranch}] in ${REPO_FILES} (or re-clone on it), or"
  log_error "  - change DeployBranch above to [${CURRENT}]."
  exit 1
fi

log_info "Repository is on [${CURRENT}], matching the deploy branch."

# The repository block records the branch at the moment you select or clone, and the pull request
# targets THAT branch — not whatever git reports now. This check reads git live, so switching
# branches after selecting a local checkout passes here while the request still aims at the old one.
# GitHub rejects that with "Validation Failed ... field: base" when the stale branch is not on the
# remote, and silently opens against the wrong branch when it is.
log_info "If you changed branches after selecting this repository above, re-select it before"
log_info "continuing, so the pull request targets [${CURRENT}] rather than the branch captured then."

# --- 2. layout ---------------------------------------------------------------
if [ -f root.hcl ]; then
  MODE="account"
  log_info "Found root.hcl — this is an existing Terragrunt Scale repository."
  log_info "This run will add the new account to it, leaving the existing configuration alone."
else
  MODE="scaffold"
  log_info "No root.hcl — this repository has not been set up for Terragrunt Scale yet."
  log_info "This run will render the full repository layout (root.hcl, .mise.toml, CI workflows) into it."
fi

echo "repo_mode=${MODE}" >> "$RUNBOOK_OUTPUT"
exit 0
