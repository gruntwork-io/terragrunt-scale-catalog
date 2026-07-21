#!/bin/bash
# Confirm the user is authenticated to GCP: an active gcloud account, working Application Default
# Credentials (which Terragrunt/OpenTofu use), and the expected active project.
set -uo pipefail

PROJECT_ID="{{ .inputs.GCPProjectID }}"
rc=0

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)
if [ -z "$ACTIVE_ACCOUNT" ]; then
  log_error "No active gcloud account. Run the 'Authenticate with gcloud' step (or 'gcloud auth login') first."
  rc=1
else
  log_info "Active gcloud account: ${ACTIVE_ACCOUNT}"
fi

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  log_info "Application Default Credentials are present and valid."
else
  log_error "Application Default Credentials are missing or expired."
  log_error "Run 'gcloud auth login --update-adc' (or 'gcloud auth application-default login') and try again."
  rc=1
fi

if [ "$rc" -ne 0 ]; then
  exit 1
fi

ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ "$ACTIVE_PROJECT" != "$PROJECT_ID" ]; then
  log_warn "Active gcloud project is '${ACTIVE_PROJECT}', but you are bootstrapping '${PROJECT_ID}'."
  log_warn "Run 'gcloud config set project ${PROJECT_ID}' if this is not what you intended."
  exit 2
fi

log_info "Authenticated to GCP and the active project is ${PROJECT_ID}."
exit 0
