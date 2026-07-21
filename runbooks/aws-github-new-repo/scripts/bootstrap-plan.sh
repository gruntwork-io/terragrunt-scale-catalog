#!/bin/bash
# Plan the bootstrap stack: the GitHub OIDC provider and the plan/apply IAM roles.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES/{{ .inputs.AccountName }}/_global/bootstrap"

log_info "Planning the bootstrap stack in {{ .inputs.AccountName }}/_global/bootstrap ..."
terragrunt run --all --non-interactive --provider-cache --backend-bootstrap plan
