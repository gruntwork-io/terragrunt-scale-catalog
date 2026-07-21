#!/bin/bash
# Apply the bootstrap stack. This creates real GCP resources (Workload Identity Pool/provider and the
# plan/apply service accounts) and the GCS state bucket. Review the plan output above before running this.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES/{{ .outputs.generate_bootstrap.bootstrap_dir }}"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply service accounts now exist in project {{ .inputs.GCPProjectID }}."
