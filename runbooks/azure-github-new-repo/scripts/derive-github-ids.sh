#!/bin/bash
# Automatically resolve the numeric GitHub org and repo IDs for the newly created repository.
# These power GitHub's immutable OIDC subject claims (required for repos created on/after 2026-07-15).
# Docs: https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
set -euo pipefail

OWNER="{{ .outputs.clone.repo_owner }}"
REPO="{{ .outputs.clone.repo_name }}"

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  log_error "Could not determine the repository owner/name from the clone step."
  exit 1
fi

log_info "Looking up numeric IDs for ${OWNER}/${REPO} via the GitHub API..."
ORG_ID=$(gh api "repos/${OWNER}/${REPO}" --jq '.owner.id')
REPO_ID=$(gh api "repos/${OWNER}/${REPO}" --jq '.id')

{
  echo "github_org_name=${OWNER}"
  echo "github_repo_name=${REPO}"
  echo "github_org_id=${ORG_ID}"
  echo "github_repo_id=${REPO_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Resolved org=${OWNER} (id ${ORG_ID}), repo=${REPO} (id ${REPO_ID})."
exit 0
