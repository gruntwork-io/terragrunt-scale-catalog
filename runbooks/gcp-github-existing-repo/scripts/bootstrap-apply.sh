#!/bin/bash
# Apply the bootstrap stack. This creates real GCP resources (Workload Identity Pool/Provider and the
# plan/apply service accounts) and the GCS state bucket. Review the plan output above before running this.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="{{ .outputs.check_gcp_auth.gcp_authenticated }}"
log_info "Applying the bootstrap stack (GCP auth confirmed: ${GCP_AUTH})..."

cd "$REPO_FILES/{{ .inputs.ProjectName }}/bootstrap"

terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply service accounts now exist in project {{ .inputs.GCPProjectID }}."
