#!/bin/bash
# Sign in to Azure and confirm the active subscription. The bootstrap step provisions resources into
# whichever subscription is active here, so this surfaces it for you to verify.
set -euo pipefail

log_info "Launching Azure sign-in (a browser window or device-code prompt may appear)..."
az login --only-show-errors >/dev/null

ACCOUNT_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

log_info "Signed in. Active subscription: ${ACCOUNT_NAME} (${SUBSCRIPTION_ID}) in tenant ${TENANT_ID}."
log_warn "If this is not the subscription you intend to bootstrap, run:"
log_warn "  az account set --subscription <id>"
log_warn "then run this step again."

echo "account_name=${ACCOUNT_NAME}" >> "$RUNBOOK_OUTPUT"
exit 0
