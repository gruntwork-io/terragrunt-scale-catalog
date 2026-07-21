#!/bin/bash
# Create the new, empty GitLab repository the Pipelines configuration will live in. It is initialized
# with a README so the deploy branch exists immediately and can be the target of the setup merge request.
set -euo pipefail

GROUP="{{ .inputs.GitLabGroupName }}"
PROJECT="{{ .inputs.GitLabProjectName }}"
DEPLOY_BRANCH="{{ .inputs.DeployBranch }}"
VISIBILITY="{{ .inputs.Visibility }}"

# Normalize visibility to a valid glab flag; default to the safest option (private).
case "$VISIBILITY" in
  public)   VIS_FLAG="--public" ;;
  internal) VIS_FLAG="--internal" ;;
  private)  VIS_FLAG="--private" ;;
  *)
    log_warn "Unrecognized visibility '${VISIBILITY}', defaulting to private."
    VIS_FLAG="--private"
    ;;
esac

log_info "Creating GitLab project ${GROUP}/${PROJECT} (${VIS_FLAG#--}, default branch ${DEPLOY_BRANCH})..."
glab repo create "${GROUP}/${PROJECT}" \
  "$VIS_FLAG" \
  --defaultBranch "$DEPLOY_BRANCH" \
  --readme \
  --description "Gruntwork Pipelines (Terragrunt Scale) infrastructure-live repository"

# Resolve the clone URL via the API so this works for self-hosted GitLab too.
ENCODED=$(printf '%s' "${GROUP}/${PROJECT}" | sed 's#/#%2F#g')
REPO_URL=$(glab api "projects/${ENCODED}" --jq '.http_url_to_repo' 2>/dev/null || true)
if [ -z "$REPO_URL" ]; then
  log_warn "Could not resolve the clone URL via the API; falling back to gitlab.com."
  REPO_URL="https://gitlab.com/${GROUP}/${PROJECT}.git"
fi

{
  echo "gitlab_group_name=${GROUP}"
  echo "gitlab_project_name=${PROJECT}"
  echo "gitlab_project_path=${GROUP}/${PROJECT}"
  echo "repo_url=${REPO_URL}"
} >> "$RUNBOOK_OUTPUT"

log_info "Created ${GROUP}/${PROJECT}. Clone it in the next step."
exit 0
