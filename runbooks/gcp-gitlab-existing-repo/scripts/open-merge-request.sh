#!/bin/bash
# Commit the generated configuration, push a branch, and open a merge request with glab.
# Opening the MR does not start a Pipelines run (commit tagged [skip ci]); Pipelines runs after you merge.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES"

BRANCH="add-gruntwork-pipelines"
DEPLOY_BRANCH="{{ .inputs.DeployBranch }}"
PROJECT="{{ .inputs.ProjectName }}"

log_info "Creating branch ${BRANCH}..."
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

git add -A
if git diff --cached --quiet; then
  log_warn "No changes to commit; the generated files may already be committed."
else
  git commit -m "Add Gruntwork Pipelines bootstrap for ${PROJECT} [skip ci]"
fi

log_info "Pushing ${BRANCH} to origin..."
git push -u origin "$BRANCH"

log_info "Opening a merge request against ${DEPLOY_BRANCH}..."
glab mr create \
  --source-branch "$BRANCH" \
  --target-branch "$DEPLOY_BRANCH" \
  --title "Add Gruntwork Pipelines bootstrap for ${PROJECT} [skip ci]" \
  --description "Adds the GitLab CI configuration and the ${PROJECT} project bootstrap (Workload Identity Pool + provider and plan/apply service accounts). Generated with a Gruntwork Runbook." \
  --yes

log_info "Merge request opened. The commit is tagged [skip ci]; no run starts yet — merge to ${DEPLOY_BRANCH} to let Pipelines take over."
exit 0
