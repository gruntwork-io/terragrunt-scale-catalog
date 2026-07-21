#!/bin/bash
# Log in to Azure with the Azure CLI. The token is cached under ~/.azure so the later Terragrunt
# steps reuse it (there is no dedicated Azure auth block; OpenTofu's azurerm/azuread providers
# authenticate via the Azure CLI).
set -euo pipefail

log_info "Logging in to Azure with the Azure CLI (device-code flow)..."
log_info "Follow the printed URL and enter the code to authenticate."
az login --use-device-code --output none

echo "azure_logged_in=true" >>"$RUNBOOK_OUTPUT"
log_info "Azure login complete. Confirm the correct subscription is active in the next step."
exit 0
