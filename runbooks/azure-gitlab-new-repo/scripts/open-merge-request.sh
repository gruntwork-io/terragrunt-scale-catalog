#!/bin/bash
# Seed the deploy branch (the project was created empty), put the generated Pipelines configuration
# on a feature branch, push, and open a merge request. The commit is tagged [skip ci], so the MR does not start a Pipelines run.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

log_info "Remote state enabled ({{ .outputs.enable_remote_state.remote_state_enabled }}). Opening the merge request..."

cd "$REPO_FILES"

DEPLOY_BRANCH="{{ .inputs.DeployBranch }}"
FEATURE_BRANCH="add-gruntwork-pipelines"
SUB="{{ .inputs.SubscriptionName }}"

# Ensure a git identity exists for the commits below.
git config user.email >/dev/null 2>&1 || git config user.email "pipelines@gruntwork.io"
git config user.name >/dev/null 2>&1 || git config user.name "Gruntwork Pipelines"

# Seed the default branch so the merge request has a target (the repo was created empty).
log_info "Seeding the ${DEPLOY_BRANCH} branch..."
git checkout -B "$DEPLOY_BRANCH"
git commit --allow-empty -m "Initialize repository [skip ci]"
git push -u origin "$DEPLOY_BRANCH"

# Put the generated Pipelines configuration on a feature branch.
log_info "Committing the generated configuration on ${FEATURE_BRANCH}..."
git checkout -B "$FEATURE_BRANCH"
git add -A
git commit -m "Add Gruntwork Pipelines bootstrap for ${SUB} [skip ci]"
git push -u origin "$FEATURE_BRANCH"

log_info "Opening a merge request from ${FEATURE_BRANCH} into ${DEPLOY_BRANCH}..."
glab mr create \
  --source-branch "$FEATURE_BRANCH" \
  --target-branch "$DEPLOY_BRANCH" \
  --title "Add Gruntwork Pipelines bootstrap for ${SUB} [skip ci]" \
  --description "Adds the Terragrunt Scale scaffold and the ${SUB} subscription bootstrap (Entra ID plan/apply apps + Azure Blob state). Generated with a Gruntwork Runbook." \
  --yes

log_info "Merge request opened. Merging it into ${DEPLOY_BRANCH} will trigger a Pipelines apply."
exit 0
