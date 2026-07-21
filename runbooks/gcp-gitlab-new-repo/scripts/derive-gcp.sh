#!/bin/bash
# Automatically resolve the numeric GCP project number from the project ID, so the user never has to
# look it up by hand. The project number powers the Workload Identity Federation principal identifiers.
set -euo pipefail

PROJECT_ID="{{ .inputs.GCPProjectID }}"

log_info "Authenticated as {{ .outputs.gcp_auth.gcp_account }}; resolving the project number for ${PROJECT_ID}..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for ${PROJECT_ID}. Check the project ID and your permissions."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Resolved project ${PROJECT_ID} to project number ${PROJECT_NUMBER}."
exit 0
