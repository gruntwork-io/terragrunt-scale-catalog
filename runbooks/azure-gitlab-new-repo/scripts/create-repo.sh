#!/bin/bash
# Create the new GitLab project in the requested group, then read back its clone URL so the
# next step (GitClone) can check it out.
set -euo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and a single pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_GitLabGroupName=$(rb_unquote "{{ .inputs.GitLabGroupName }}")
RB_GitLabProjectName=$(rb_unquote "{{ .inputs.GitLabProjectName }}")
RB_Visibility=$(rb_unquote "{{ .inputs.Visibility }}")

GROUP="${RB_GitLabGroupName}"
PROJECT="${RB_GitLabProjectName}"
VISIBILITY="${RB_Visibility}"
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
