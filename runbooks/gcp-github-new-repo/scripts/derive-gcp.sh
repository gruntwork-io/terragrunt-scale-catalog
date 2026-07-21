#!/bin/bash
# Automatically derive the numeric GCP project number from the project ID the user entered,
# so the user never has to look it up by hand.
# This step needs active GCP Application Default Credentials, verified by the authentication
# check ({{ .outputs.gcp_check.gcp_adc_active }}), which gates this block until it has run.
set -euo pipefail

PROJECT_ID="{{ .inputs.GCPProjectID }}"

if [ -z "$PROJECT_ID" ]; then
  log_error "GCPProjectID is empty. Fill in the bootstrap settings form first."
  exit 1
fi

log_info "Deriving the GCP project number for ${PROJECT_ID}..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_NUMBER" ]; then
  log_error "Could not resolve a project number for ${PROJECT_ID}."
  log_error "Check the project ID and that your account has access (try 'gcloud auth login')."
  exit 1
fi

echo "gcp_project_number=${PROJECT_NUMBER}" >> "$RUNBOOK_OUTPUT"

log_info "Project ${PROJECT_ID} has number ${PROJECT_NUMBER}."
exit 0
