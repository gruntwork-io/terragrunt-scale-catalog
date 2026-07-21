#!/bin/bash
# Plan the bootstrap stack: the GitHub Workload Identity Pool/Provider and the plan/apply service accounts.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="{{ .outputs.check_gcp_auth.gcp_authenticated }}"
log_info "Planning the bootstrap stack (GCP auth confirmed: ${GCP_AUTH})..."

cd "$REPO_FILES/{{ .inputs.ProjectName }}/bootstrap"

log_info "Planning in {{ .inputs.ProjectName }}/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache --backend-bootstrap plan
