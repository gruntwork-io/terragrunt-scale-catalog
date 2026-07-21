#!/bin/bash
# Confirm the plan/apply service accounts created by the bootstrap stack exist in the project.
# References the GCP auth check output so this stays gated until you have authenticated.
set -uo pipefail

log_info "Verifying service accounts (GCP access ready: {{ .outputs.gcp_auth_check.gcp_ready }})."

PREFIX="{{ .inputs.OIDCResourcePrefix }}"
PROJECT_ID="{{ .inputs.GCPProjectID }}"
rc=0
for sa in "${PREFIX}-plan" "${PREFIX}-apply"; do
  EMAIL="${sa}@${PROJECT_ID}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
    log_info "Service account ${EMAIL} exists."
  else
    log_error "Service account ${EMAIL} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both Pipelines service accounts are present."
fi
exit "$rc"
