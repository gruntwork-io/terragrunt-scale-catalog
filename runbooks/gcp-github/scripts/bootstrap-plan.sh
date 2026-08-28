#!/bin/bash
# Plan the bootstrap stack: the GitHub Workload Identity Pool/Provider and the plan/apply service accounts.
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

RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
RB_out_check_gcp_auth_gcp_authenticated=$(rb_unquote "{{ .outputs.check_gcp_auth.gcp_authenticated }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="${RB_out_check_gcp_auth_gcp_authenticated}"
log_info "Planning the bootstrap stack (GCP auth confirmed: ${GCP_AUTH})..."

cd "$REPO_FILES/${RB_ProjectName}/bootstrap"

log_info "Planning in ${RB_ProjectName}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache --backend-bootstrap plan
