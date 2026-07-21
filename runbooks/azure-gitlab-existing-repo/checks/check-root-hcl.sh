#!/bin/bash
# The azure/gitlab/subscription template does NOT create root.hcl. An existing Terragrunt Scale repo
# is expected to already have one at its root (it configures the azurerm remote-state backend and the
# azurerm/azuread providers). A later step in this runbook will add these blocks if they are missing.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

if [ -f "$REPO_FILES/root.hcl" ]; then
  log_info "Found root.hcl at the repository root."
  if grep -q "azurerm" "$REPO_FILES/root.hcl"; then
    log_info "root.hcl references the azurerm backend."
  else
    log_warn "root.hcl does not yet reference the azurerm backend; the runbook will add it in a later step."
  fi
  exit 0
else
  log_warn "No root.hcl found at the repository root."
  log_warn "The subscription template does not create one. The runbook will scaffold the Azure backend and"
  log_warn "providers for you, but confirm this is an existing Terragrunt Scale repository before continuing."
  exit 2
fi
