#!/bin/bash
# Configure Google Cloud Application Default Credentials. This runs interactively with a PTY, so the
# browser/device-code prompt is shown in the log; complete the sign-in to finish authentication.
# ADC is written to a well-known location and is picked up automatically by gcloud, OpenTofu, and
# Terragrunt in the subsequent steps.
set -euo pipefail

log_info "Launching 'gcloud auth application-default login'..."
log_info "Follow the browser (or device-code) prompt below to grant Application Default Credentials."
gcloud auth application-default login

echo "adc_configured=true" >> "$RUNBOOK_OUTPUT"

log_info "Application Default Credentials configured."
exit 0
