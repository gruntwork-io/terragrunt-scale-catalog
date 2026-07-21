#!/bin/bash
# Commit the generated Pipelines configuration, push a setup branch, and open a merge request.
# glab authenticates with the session GITLAB_TOKEN established by the GitLab auth step.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES"

BRANCH="add-gruntwork-pipelines"
ACCOUNT_NAME="{{ .inputs.AccountName }}"
DEPLOY_BRANCH="{{ .inputs.DeployBranch }}"

# Ensure a committer identity exists in this non-interactive shell.
git config user.name >/dev/null 2>&1  || git config user.name "Gruntwork Runbook"
git config user.email >/dev/null 2>&1 || git config user.email "runbook@gruntwork.io"

# Create (or switch to) the setup branch.
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

# Stage and commit everything the runbook generated.
git add -A
if git diff --cached --quiet; then
  log_warn "No staged changes to commit. Did the generate step run? Continuing to push the branch."
else
  git commit -m "Add Gruntwork Pipelines bootstrap for ${ACCOUNT_NAME} [skip ci]"
fi

# Push the setup branch. The commit is tagged [skip ci], so pushing does not start a Pipelines run.
log_info "Pushing ${BRANCH} to origin..."
git push -u origin "$BRANCH"

# Open a merge request via glab (uses the session GITLAB_TOKEN).
if command -v glab >/dev/null 2>&1; then
  log_info "Opening a merge request via glab..."
  if glab mr create \
      --fill \
      --source-branch "$BRANCH" \
      --target-branch "$DEPLOY_BRANCH" \
      --yes; then
    log_info "Merge request opened. The commit is tagged [skip ci]; no Pipelines run starts until you merge."
  else
    log_warn "glab could not open the merge request automatically."
    log_warn "The branch '${BRANCH}' has been pushed — open a merge request into '${DEPLOY_BRANCH}'"
    log_warn "from the link above or the GitLab UI. Pushing the branch is all that's required."
  fi
else
  log_warn "glab CLI not found. The branch '${BRANCH}' has been pushed to origin."
  log_warn "Open a merge request into '${DEPLOY_BRANCH}' from the GitLab UI. The commit is tagged [skip ci], so Pipelines runs only after you merge."
fi

exit 0
