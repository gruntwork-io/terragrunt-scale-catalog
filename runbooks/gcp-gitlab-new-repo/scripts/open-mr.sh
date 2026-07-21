#!/bin/bash
# Commit the generated configuration on a feature branch, push it, and open a merge request against the
# deploy branch. Opening the MR does not start a Pipelines run (commit tagged [skip ci]); Pipelines runs after you merge.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES"

BRANCH="add-gruntwork-pipelines"
TARGET="{{ .inputs.DeployBranch }}"
PROJECT_PATH="{{ .inputs.GitLabGroupName }}/{{ .inputs.GitLabProjectName }}"

# Ensure a commit identity exists (the runbook shell may not have one configured).
git config user.email >/dev/null 2>&1 || git config user.email "pipelines-bootstrap@users.noreply.gitlab.com"
git config user.name  >/dev/null 2>&1 || git config user.name  "Gruntwork Pipelines Bootstrap"

log_info "Creating branch ${BRANCH} and committing the generated configuration..."
git checkout -b "$BRANCH"
git add -A
git commit -m "Add Gruntwork Pipelines bootstrap for {{ .inputs.ProjectName }} [skip ci]"

log_info "Pushing ${BRANCH} to origin..."
git push -u origin "$BRANCH"

log_info "Opening a merge request against ${TARGET}..."
glab mr create \
  --repo "$PROJECT_PATH" \
  --source-branch "$BRANCH" \
  --target-branch "$TARGET" \
  --title "Add Gruntwork Pipelines bootstrap for {{ .inputs.ProjectName }} [skip ci]" \
  --description "Adds the GitLab CI pipeline and the {{ .inputs.ProjectName }} project bootstrap (Workload Identity Pool/provider + plan/apply service accounts). Generated with a Gruntwork Runbook." \
  --yes

log_info "Merge request opened against ${TARGET}."
exit 0
