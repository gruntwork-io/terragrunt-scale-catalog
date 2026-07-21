#!/bin/bash
# Automatically resolve the numeric GCP project number from the project ID, so the user never has
# to look it up. The project number is used by the Workload Identity bindings the bootstrap creates.
# References the GCP auth check output so this stays gated until authentication succeeds.
set -euo pipefail

PROJECT_ID="{{ .inputs.GCPProjectID }}"

log_info "Deriving the project number for ${PROJECT_ID} (GCP access ready: {{ .outputs.gcp_auth_check.gcp_ready }})..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for '${PROJECT_ID}'. Check the project ID and that you have access."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Resolved project ${PROJECT_ID} -> project number ${PROJECT_NUMBER}."
exit 0
