#!/bin/bash
# Apply the bootstrap stack. This creates real GCP resources (Workload Identity Pool + provider,
# plan/apply service accounts and IAM bindings) and the GCS state bucket. Review the plan output
# above before running this.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES/{{ .inputs.ProjectName }}/bootstrap"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply service accounts now exist in project {{ .inputs.GCPProjectID }}."
