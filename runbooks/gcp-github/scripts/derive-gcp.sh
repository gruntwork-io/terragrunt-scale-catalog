#!/bin/bash
# Automatically derive the numeric GCP project number from the project ID, so the user never has to
# look it up by hand. The project number is required for the Workload Identity Pool resource path.
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

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_out_check_gcp_auth_gcp_authenticated=$(rb_unquote "{{ .outputs.check_gcp_auth.gcp_authenticated }}")

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="${RB_out_check_gcp_auth_gcp_authenticated}"
PROJECT_ID="${RB_GCPProjectID}"
log_info "Deriving the project number for ${PROJECT_ID} (GCP auth confirmed: ${GCP_AUTH})..."

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for ${PROJECT_ID}. Check the project ID and your permissions."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Project ${PROJECT_ID} has project number ${PROJECT_NUMBER}."
exit 0
