#!/bin/bash
# Commit the generated configuration on a setup branch and open a pull request with the gh CLI. The commit
# message carries [skip ci], so opening the PR does not start a Pipelines run before you are ready. gh and
# git push authenticate with the session GITHUB_TOKEN established by the GitHub auth step.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES"

BRANCH="add-gruntwork-pipelines"
BASE="{{ .inputs.DeployBranch }}"
TITLE="Add Gruntwork Pipelines bootstrap for {{ .inputs.ProjectName }} [skip ci]"
BODY="Adds the Pipelines GitHub Actions workflow and the {{ .inputs.ProjectName }} project bootstrap (Workload Identity Pool + plan/apply service accounts). Generated with a Gruntwork Runbook."

# Ensure a committer identity exists in this non-interactive shell.
git config user.name  >/dev/null 2>&1 || git config user.name  "Gruntwork Runbook"
git config user.email >/dev/null 2>&1 || git config user.email "runbook@gruntwork.io"

# Configure git to authenticate to github.com with the gh token so the push below succeeds.
gh auth setup-git >/dev/null 2>&1 || true

# Create (or switch to) the setup branch.
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

# Stage and commit everything the runbook generated. The [skip ci] tag keeps this off Pipelines.
git add -A
if git diff --cached --quiet; then
  log_warn "No staged changes to commit. Did the generate step run? Continuing to push the branch."
else
  git commit -m "$TITLE"
fi

log_info "Pushing ${BRANCH} to origin..."
git push -u origin "$BRANCH"

# Open the pull request (gh uses the session GITHUB_TOKEN). Idempotent: reuse an existing PR if present.
if gh pr view "$BRANCH" --json url --jq '.url' >/dev/null 2>&1; then
  log_info "A pull request already exists for ${BRANCH}:"
  gh pr view "$BRANCH" --json url --jq '.url'
else
  log_info "Opening a pull request into ${BASE}..."
  gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body "$BODY"
fi

log_info "Done. The PR commit is tagged [skip ci]; Pipelines runs once you merge to ${BASE}."
exit 0
