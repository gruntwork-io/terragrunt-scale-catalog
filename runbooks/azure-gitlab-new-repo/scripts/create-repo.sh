#!/bin/bash
# Create the new GitLab project in the requested group, then read back its clone URL so the
# next step (GitClone) can check it out.
set -euo pipefail

GROUP="{{ .inputs.GitLabGroupName }}"
PROJECT="{{ .inputs.GitLabProjectName }}"
VISIBILITY="{{ .inputs.Visibility }}"
FULL_PATH="${GROUP}/${PROJECT}"

case "$VISIBILITY" in
  public) VIS_FLAG="--public" ;;
  internal) VIS_FLAG="--internal" ;;
  *) VIS_FLAG="--private" ;;
esac

if glab repo view "$FULL_PATH" >/dev/null 2>&1; then
  log_warn "Project ${FULL_PATH} already exists; reusing it."
else
  log_info "Creating GitLab project ${FULL_PATH} (${VISIBILITY})..."
  glab repo create "$FULL_PATH" "$VIS_FLAG" \
    --description "Terragrunt Scale infrastructure-live repository managed by Gruntwork Pipelines."
fi

# Resolve the clone URL via the API so this works for self-hosted GitLab too.
ENCODED=$(printf '%s' "$FULL_PATH" | sed 's#/#%2F#g')
REPO_URL=$(glab api "projects/${ENCODED}" --jq '.http_url_to_repo')
WEB_URL=$(glab api "projects/${ENCODED}" --jq '.web_url')

if [ -z "$REPO_URL" ]; then
  log_error "Could not resolve the clone URL for ${FULL_PATH}."
  exit 1
fi

{
  echo "repo_path=${FULL_PATH}"
  echo "repo_url=${REPO_URL}"
  echo "repo_web_url=${WEB_URL}"
} >>"$RUNBOOK_OUTPUT"

log_info "Project ready at ${WEB_URL}"
exit 0
