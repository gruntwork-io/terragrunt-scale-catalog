#!/bin/bash
# Establish GCP Application Default Credentials for Terragrunt/OpenTofu. Skips the interactive
# login if valid credentials are already present.
set -euo pipefail

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  log_info "Application Default Credentials already present; skipping interactive login."
else
  log_info "Launching gcloud Application Default Credentials login..."
  gcloud auth application-default login
fi

ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
if [ -z "$ACCOUNT" ]; then
  log_warn "No active gcloud CLI account detected. If 'gcloud projects describe' fails later,"
  log_warn "run 'gcloud auth login' to authenticate the CLI itself."
else
  log_info "Authenticated to GCP as ${ACCOUNT}."
fi
exit 0
