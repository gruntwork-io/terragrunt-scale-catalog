#!/bin/bash
# Confirm gcloud can mint an access token before we try to provision anything.
# Emits gcp_ready so downstream GCP steps stay disabled until authentication succeeds.
set -uo pipefail

if gcloud auth print-access-token >/dev/null 2>&1; then
  ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
  log_info "gcloud has a valid access token${ACCOUNT:+ for account ${ACCOUNT}}."
  echo "gcp_ready=true" >> "$RUNBOOK_OUTPUT"
  exit 0
fi

log_error "Could not obtain an access token from gcloud."
log_error "Run 'gcloud auth login' (for gcloud CLI commands) and 'gcloud auth application-default login'"
log_error "(so Terragrunt/OpenTofu can authenticate), then run this check again."
exit 1
