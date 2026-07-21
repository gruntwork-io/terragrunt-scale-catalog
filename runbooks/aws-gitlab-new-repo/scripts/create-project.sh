#!/bin/bash
# Create the new GitLab project that will hold the infrastructure-live scaffold.
# The project is created empty; later steps render the Pipelines scaffold into it.
# glab authenticates with the session GITLAB_TOKEN established by the GitLab auth step.
set -euo pipefail

GROUP="{{ .inputs.GitLabGroupName }}"
PROJECT="{{ .inputs.GitLabProjectName }}"
VISIBILITY="{{ .inputs.Visibility }}"

if [ -z "$GROUP" ] || [ -z "$PROJECT" ]; then
  log_error "GitLabGroupName and GitLabProjectName are required."
  exit 1
fi

if glab repo view "${GROUP}/${PROJECT}" >/dev/null 2>&1; then
  log_warn "Project ${GROUP}/${PROJECT} already exists; skipping creation."
else
  log_info "Creating GitLab project ${GROUP}/${PROJECT} (${VISIBILITY})..."
  glab repo create "${GROUP}/${PROJECT}" "--${VISIBILITY}"
  log_info "Created ${GROUP}/${PROJECT}."
fi

# Resolve the clone URL via the API so this works for self-hosted GitLab too.
ENCODED=$(printf '%s' "${GROUP}/${PROJECT}" | sed 's#/#%2F#g')
REPO_URL=$(glab api "projects/${ENCODED}" --jq '.http_url_to_repo' 2>/dev/null || true)
if [ -z "$REPO_URL" ]; then
  log_warn "Could not resolve the clone URL via the API; falling back to gitlab.com."
  REPO_URL="https://gitlab.com/${GROUP}/${PROJECT}.git"
fi

{
  echo "project_name=${PROJECT}"
  echo "project_path=${GROUP}/${PROJECT}"
  echo "repo_url=${REPO_URL}"
} >> "$RUNBOOK_OUTPUT"

log_info "Project ready at ${GROUP}/${PROJECT}."
exit 0
