#!/bin/bash
# Seed the deploy branch (the new repository is empty), commit the generated Pipelines scaffold on a
# setup branch, push it, and open a merge request. glab authenticates with the session GITLAB_TOKEN
# established by the GitLab auth step.
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

# The new project has no commits yet. Seed an empty deploy branch first so the merge request has a
# target to open against. The [skip ci] marker keeps this seed commit from triggering a pipeline
# (the deploy branch has no .gitlab-ci.yml until the setup branch merges).
if git ls-remote --exit-code --heads origin "$DEPLOY_BRANCH" >/dev/null 2>&1; then
  log_info "Deploy branch ${DEPLOY_BRANCH} already exists on the remote; not re-seeding it."
  git fetch origin "$DEPLOY_BRANCH" >/dev/null 2>&1 || true
else
  log_info "New repository has no ${DEPLOY_BRANCH} branch yet; seeding an empty initial commit..."
  git checkout -B "$DEPLOY_BRANCH"
  git commit --allow-empty -m "Initialize repository [skip ci]"
  git push -u origin "$DEPLOY_BRANCH"
fi

# Put the generated scaffold on the setup branch, based on the deploy branch we just seeded.
git checkout -B "$BRANCH"

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
