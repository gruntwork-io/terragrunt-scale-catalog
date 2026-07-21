#!/bin/bash
# Create the new GitHub repository. It is created with an initial commit (--add-readme) so it has a
# default branch, which the setup pull request is opened against later. Idempotent: skips if it exists.
set -euo pipefail

ORG="{{ .inputs.GitHubOrgName }}"
REPO="{{ .inputs.GitHubRepoName }}"
VISIBILITY="{{ .inputs.Visibility }}"
FULL="${ORG}/${REPO}"

if [ -z "$ORG" ] || [ -z "$REPO" ]; then
  log_error "GitHubOrgName and GitHubRepoName are required."
  exit 1
fi

if gh repo view "$FULL" >/dev/null 2>&1; then
  log_warn "Repository ${FULL} already exists; skipping creation."
else
  log_info "Creating ${VISIBILITY} repository ${FULL} with an initial commit..."
  gh repo create "$FULL" --"$VISIBILITY" --add-readme
  log_info "Created ${FULL}."
fi

REPO_URL="https://github.com/${FULL}"
{
  echo "repo_full_name=${FULL}"
  echo "repo_owner=${ORG}"
  echo "repo_name=${REPO}"
  echo "repo_url=${REPO_URL}"
} >> "$RUNBOOK_OUTPUT"

log_info "Repository ${FULL} is ready to clone."
exit 0
