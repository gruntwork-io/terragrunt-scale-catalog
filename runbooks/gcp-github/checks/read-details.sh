#!/bin/bash
# Read everything the rest of the runbook is shaped by, in one pass, and publish it:
#
#   gcp_project_number - the numeric project number for the project ID you gave, required for the
#                        Workload Identity Pool resource path
#   deploy_branch      - the branch the clone is on. Pipelines applies on merges here, and the setup
#                        pull request targets it. Read from the repository so the two cannot disagree.
#   repo_mode          - "account" when a root `root.hcl` is present (an existing Terragrunt Scale
#                        repository: only the new project is added), "scaffold" when it is absent.
#
# Nothing is changed here — this only looks.
set -uo pipefail

rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_out_check_gcp_auth_gcp_authenticated=$(rb_unquote "{{ .outputs.check_gcp_auth.gcp_authenticated }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  log_error "If the repository has no commits yet, use the clone block's **Create default branch**"
  log_error "button — the clone holds back its outputs until the branch exists."
  exit 1
fi

if [ -z "$RB_GCPProjectID" ]; then
  log_error "GCPProjectID is empty. Fill in the bootstrap settings above."
  exit 1
fi

# --- GCP project -------------------------------------------------------------
# Application Default Credentials expire like any other session; say so plainly rather than letting
# a raw gcloud error surface further in. (GCP auth confirmed earlier: ${RB_out_check_gcp_auth_gcp_authenticated})
if ! PROJECT_NUMBER=$(gcloud projects describe "$RB_GCPProjectID" --format='value(projectNumber)' 2>&1); then
  log_error "Could not read project ${RB_GCPProjectID}: ${PROJECT_NUMBER}"
  log_error "Re-run the GCP authentication step above to refresh your credentials, or check the"
  log_error "project ID and that your account has access to it."
  exit 1
fi

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for ${RB_GCPProjectID}. Check the project ID and your permissions."
  exit 1
fi

log_info "GCP project:   ${RB_GCPProjectID}  (number ${PROJECT_NUMBER})"

# --- the repository ----------------------------------------------------------
cd "$REPO_FILES"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  log_error "Could not determine the current branch of ${REPO_FILES}."
  log_error "A detached HEAD or a repository with no commits has no branch to deploy from."
  log_error "Check out the branch Pipelines should deploy from, then run this check again."
  exit 1
fi

if [ -f root.hcl ]; then MODE="account"; else MODE="scaffold"; fi

log_info "Deploy branch: ${BRANCH}  (read from the repository, not typed)"
log_info "Repository:    ${MODE}"
if [ "$MODE" = "account" ]; then
  log_info "  Found root.hcl — an existing Terragrunt Scale repository. This run adds the new"
  log_info "  project to it and leaves the existing configuration alone."
else
  log_info "  No root.hcl — not set up for Terragrunt Scale yet. This run renders the full"
  log_info "  repository layout (root.hcl, .mise.toml, CI workflows) into it."
fi

log_info "If you changed branches after selecting the repository above, select it again so the"
log_info "pull request targets ${BRANCH} too."

{
  echo "gcp_project_number=${PROJECT_NUMBER}"
  echo "deploy_branch=${BRANCH}"
  echo "repo_mode=${MODE}"
} >> "$RUNBOOK_OUTPUT"
exit 0
