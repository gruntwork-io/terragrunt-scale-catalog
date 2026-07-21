#!/bin/bash
# Confirm the plan/apply service accounts created by the bootstrap stack exist in the project.
set -uo pipefail

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="{{ .outputs.check_gcp_auth.gcp_authenticated }}"
log_info "Checking service accounts (GCP auth confirmed: ${GCP_AUTH})..."

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
  log_info "Both plan/apply service accounts are present."
fi
exit "$rc"
