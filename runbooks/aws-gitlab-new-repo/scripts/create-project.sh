#!/bin/bash
# Create the new GitLab project that will hold the infrastructure-live scaffold.
# The project is created empty; later steps render the Pipelines scaffold into it.
# glab authenticates with the session GITLAB_TOKEN established by the GitLab auth step.
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
