#!/bin/bash
# Check the branch the setup pull request will push to is free.
#
# The request is pushed without --force, so if a branch of the same name already exists on the
# remote and has commits this run does not have, the push is rejected as non-fast-forward — after
# the runbook has already generated and committed its work. Detect it here, while the fix is cheap.
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

RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
BRANCH="add-gruntwork-pipelines-${RB_ProjectName}"

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  exit 1
fi

cd "$REPO_FILES"

if ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  log_info "Branch [${BRANCH}] is free on the remote; the setup pull request can push to it."
  exit 0
fi

log_warn "Branch [${BRANCH}] already exists on the remote, probably from an earlier run."
log_warn "The pull request step pushes without --force, so it will be rejected as non-fast-forward."
log_warn "Pick one before continuing:"
log_warn "  - edit the branch name in the pull request step below (it is an editable field), or"
log_warn "  - delete the stale branch:  git -C ${REPO_FILES} push origin --delete ${BRANCH}"
log_warn "    (close any pull request opened from it first), or"
log_warn "  - fold in its commits:  git -C ${REPO_FILES} fetch origin && git rebase origin/${BRANCH}"
exit 2
