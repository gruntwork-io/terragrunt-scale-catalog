#!/bin/bash
# Automatically resolve the numeric GCP project number from the project ID, so the user never has
# to look it up. The project number is used by the Workload Identity bindings the bootstrap creates.
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

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_out_gcp_auth_check_gcp_ready=$(rb_unquote "{{ .outputs.gcp_auth_check.gcp_ready }}")

PROJECT_ID="${RB_GCPProjectID}"

log_info "Deriving the project number for ${PROJECT_ID} (GCP access ready: ${RB_out_gcp_auth_check_gcp_ready})..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for '${PROJECT_ID}'. Check the project ID and that you have access."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Resolved project ${PROJECT_ID} -> project number ${PROJECT_NUMBER}."
exit 0
