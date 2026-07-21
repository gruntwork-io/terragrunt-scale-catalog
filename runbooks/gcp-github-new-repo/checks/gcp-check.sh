#!/bin/bash
# Confirm GCP Application Default Credentials are active by requesting an access token.
# Emits the active account so later steps can enforce ordering on this check.
set -uo pipefail

if ! command -v gcloud >/dev/null 2>&1; then
  log_error "gcloud CLI not found. Complete the pre-flight checks first."
  exit 1
fi

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
  log_info "Application Default Credentials are active${ACCOUNT:+ (account: ${ACCOUNT})}."
  {
    echo "gcp_adc_active=true"
    echo "gcp_account=${ACCOUNT}"
  } >> "$RUNBOOK_OUTPUT"
  exit 0
fi

log_error "No active Application Default Credentials found."
log_error "Run the previous step (gcloud auth application-default login) and try again."
exit 1
