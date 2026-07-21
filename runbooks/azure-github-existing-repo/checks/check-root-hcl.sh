#!/bin/bash
# The azure/github/subscription template does NOT create root.hcl (that content lives in the
# azure/base layer, which only brand-new repos pull in). This check just reports the current state of
# the cloned repo; the 'Ensure the repository root configuration' step adds root.hcl if it is missing,
# so it is fine if this warns.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

if [ -f "$REPO_FILES/root.hcl" ]; then
  if grep -q 'remote_state' "$REPO_FILES/root.hcl"; then
    log_info "Found root.hcl with a remote_state block."
  else
    log_info "Found root.hcl (no remote_state block yet; it will be added in a later step)."
  fi
  exit 0
else
  log_warn "No root.hcl at the repository root."
  log_warn "That's expected for a repo not yet set up for Terragrunt Scale on Azure."
  log_warn "The 'Ensure the repository root configuration' step will create it for you."
  exit 2
fi
