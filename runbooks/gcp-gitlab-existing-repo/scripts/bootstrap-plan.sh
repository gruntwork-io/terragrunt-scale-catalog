#!/bin/bash
# Plan the bootstrap stack: the Workload Identity Pool/provider and the plan/apply service accounts.
# References the GCP auth check output so this stays gated until authentication succeeds.
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
RB_out_gcp_auth_check_gcp_ready=$(rb_unquote "{{ .outputs.gcp_auth_check.gcp_ready }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

log_info "GCP access ready: ${RB_out_gcp_auth_check_gcp_ready}"

cd "$REPO_FILES/${RB_ProjectName}/bootstrap"

log_info "Planning the bootstrap stack in ${RB_ProjectName}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache --backend-bootstrap plan
