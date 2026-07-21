#!/bin/bash
# Automatically derive the numeric GCP project number from the project ID, so the user never has to
# look it up by hand. The project number is required for the Workload Identity Pool resource path.
set -euo pipefail

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="{{ .outputs.check_gcp_auth.gcp_authenticated }}"
PROJECT_ID="{{ .inputs.GCPProjectID }}"
log_info "Deriving the project number for ${PROJECT_ID} (GCP auth confirmed: ${GCP_AUTH})..."

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for ${PROJECT_ID}. Check the project ID and your permissions."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Project ${PROJECT_ID} has project number ${PROJECT_NUMBER}."
exit 0
