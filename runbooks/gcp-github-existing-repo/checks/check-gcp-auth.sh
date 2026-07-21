#!/bin/bash
# Confirm Application Default Credentials are configured and usable.
# Gated on the login command having run (references its output below).
set -uo pipefail

# Ordering guard: this check is enabled only after the GCP login step has completed.
GCP_LOGIN_DONE="{{ .outputs.gcp_auth.adc_configured }}"
log_info "Verifying Application Default Credentials (login step reported: ${GCP_LOGIN_DONE})..."

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  log_info "Application Default Credentials are valid."
  echo "gcp_authenticated=true" >> "$RUNBOOK_OUTPUT"
  exit 0
else
  log_error "Could not obtain an access token from Application Default Credentials."
  log_error "Re-run the 'Google Cloud application-default login' step and complete the sign-in."
  exit 1
fi
