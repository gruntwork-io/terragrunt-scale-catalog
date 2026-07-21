#!/bin/bash
# Create the new GitHub repository that will hold the infrastructure-live scaffold.
# The repository is created empty; later steps render the Pipelines scaffold into it.
set -euo pipefail

ORG="{{ .inputs.GitHubOrgName }}"
REPO="{{ .inputs.GitHubRepoName }}"
VISIBILITY="{{ .inputs.Visibility }}"

if [ -z "$ORG" ] || [ -z "$REPO" ]; then
  log_error "GitHubOrgName and GitHubRepoName are required."
  exit 1
fi

if gh repo view "${ORG}/${REPO}" >/dev/null 2>&1; then
  log_warn "Repository ${ORG}/${REPO} already exists; skipping creation."
else
  log_info "Creating GitHub repository ${ORG}/${REPO} (${VISIBILITY})..."
  gh repo create "${ORG}/${REPO}" "--${VISIBILITY}"
  log_info "Created ${ORG}/${REPO}."
fi

REPO_URL="https://github.com/${ORG}/${REPO}"
{
  echo "repo_url=${REPO_URL}"
  echo "repo_full_name=${ORG}/${REPO}"
} >> "$RUNBOOK_OUTPUT"

log_info "Repository ready at ${REPO_URL}."
exit 0
