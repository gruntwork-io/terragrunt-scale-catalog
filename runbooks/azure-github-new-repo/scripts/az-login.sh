#!/bin/bash
# Authenticate the Azure CLI. This runs interactively with a PTY, so the browser/device-code prompt is
# shown in the log; complete the sign-in to finish authentication. The resulting credentials are written
# to a well-known location and are picked up automatically by 'az', the azurerm provider, and the azuread
# provider in the subsequent steps.
set -euo pipefail

if az account show >/dev/null 2>&1; then
  log_info "Already authenticated to Azure as $(az account show --query user.name -o tsv 2>/dev/null || echo 'the current user')."
else
  log_info "Launching 'az login'. Complete the sign-in via the browser (or device-code) prompt below..."
  az login
fi

log_info "Active subscription: $(az account show --query name -o tsv) ($(az account show --query id -o tsv))."
log_info "If this is not the subscription you want to bootstrap, run 'az account set --subscription <id>' and re-run this step."

echo "azure_logged_in=true" >> "$RUNBOOK_OUTPUT"
exit 0
