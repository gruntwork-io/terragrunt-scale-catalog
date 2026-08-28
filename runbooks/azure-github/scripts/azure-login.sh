#!/bin/bash
# Authenticate to Azure. Opens an interactive `az login` (browser/device code) so this runbook can read
# your tenant/subscription IDs and drive Terragrunt against the subscription you select.
set -euo pipefail

log_info "Launching az login. Complete the sign-in, then confirm the active subscription below."
az login

log_info "Active Azure context:"
az account show --query '{subscription:name, subscriptionId:id, tenantId:tenantId, user:user.name}' -o table || true

log_info "If the wrong subscription is active, run 'az account set --subscription <id>' before continuing."
exit 0
