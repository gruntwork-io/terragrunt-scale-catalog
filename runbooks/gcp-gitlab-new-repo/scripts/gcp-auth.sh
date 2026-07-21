#!/bin/bash
# Authenticate to GCP with the gcloud CLI. There is no dedicated GCP auth block, so we drive gcloud
# directly: log the user in, update Application Default Credentials (used by Terragrunt/OpenTofu's
# Google provider), and set the active project. Login opens a browser to complete the flow.
set -euo pipefail

PROJECT_ID="{{ .inputs.GCPProjectID }}"

log_info "Logging in to gcloud and updating Application Default Credentials (a browser window will open)..."
gcloud auth login --update-adc

log_info "Setting the active project to ${PROJECT_ID}..."
gcloud config set project "$PROJECT_ID"

# Set the ADC quota/billing project so client libraries (and OpenTofu) don't warn about an unset one.
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null 2>&1 \
  || log_warn "Could not set the ADC quota project; continuing (this is usually harmless)."

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)

{
  echo "gcp_account=${ACTIVE_ACCOUNT}"
  echo "gcp_project_id=${PROJECT_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Authenticated to GCP as ${ACTIVE_ACCOUNT} (project ${PROJECT_ID})."
exit 0
