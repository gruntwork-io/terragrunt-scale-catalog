#!/bin/bash
# The aws/github/account template does NOT create root.hcl. An existing Terragrunt Scale repo
# is expected to already have one at its root (it configures the S3 remote state backend).
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

if [ -f "$REPO_FILES/root.hcl" ]; then
  log_info "Found root.hcl at the repository root."
  exit 0
else
  log_warn "No root.hcl found at the repository root."
  log_warn "The account template does not create one. If your repo does not already have a root.hcl"
  log_warn "configuring the S3 backend, contact Gruntwork support before continuing."
  exit 2
fi
