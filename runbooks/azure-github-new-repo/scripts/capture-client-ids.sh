#!/bin/bash
# Read the plan/apply application client IDs from the applied bootstrap stack and write them into the
# environment HCL, replacing the FIXME placeholders. This runs BEFORE the remote-state is enabled, so the
# stack outputs are read from the still-local OpenTofu state.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"
export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"

# Ordering guard: enabled only after the bootstrap apply step has completed.
APPLY_DONE="{{ .outputs.bootstrap_apply.bootstrap_applied }}"

SUB="{{ .inputs.SubscriptionName }}"
BOOTSTRAP_DIR="$REPO_FILES/${SUB}/bootstrap"
ENV_HCL="$REPO_FILES/.gruntwork/environment-${SUB}.hcl"

if [ ! -f "$ENV_HCL" ]; then
  log_error "Expected environment file not found: ${ENV_HCL}"
  exit 1
fi

cd "$BOOTSTRAP_DIR"

log_info "Reading the plan/apply client IDs from the bootstrap stack outputs (apply: ${APPLY_DONE})..."
STACK_OUTPUT=$(terragrunt stack output --no-stack-generate --non-interactive -json)

extract_client_id() {
  # $1 = plan_app | apply_app. Outputs may be nested under the stack name ("bootstrap") or at the top
  # level, and client_id may be a raw string or {value,type}-wrapped.
  jq -r --arg app "$1" '
    ((.bootstrap[$app] // .[$app]) // {}) as $a
    | ($a.client_id | if type == "object" then .value else . end) // empty
  ' <<<"$STACK_OUTPUT"
}

PLAN_CLIENT_ID=$(extract_client_id plan_app)
APPLY_CLIENT_ID=$(extract_client_id apply_app)

if [ -z "$PLAN_CLIENT_ID" ] || [ -z "$APPLY_CLIENT_ID" ]; then
  log_error "Could not read the plan/apply client IDs from 'terragrunt stack output'."
  log_error "Confirm the bootstrap apply step completed successfully."
  exit 1
fi

log_info "Writing the client IDs into ${ENV_HCL}..."
sed -i.bak \
  -e "s|plan_client_id[[:space:]]*=[[:space:]]*\"\".*|plan_client_id  = \"${PLAN_CLIENT_ID}\"|" \
  -e "s|apply_client_id[[:space:]]*=[[:space:]]*\"\".*|apply_client_id = \"${APPLY_CLIENT_ID}\"|" \
  "$ENV_HCL"
rm -f "${ENV_HCL}.bak"

if grep -q 'FIXME: Fill in the client ID' "$ENV_HCL"; then
  log_error "The FIXME client-id placeholders are still present in ${ENV_HCL}."
  exit 1
fi

echo "client_ids_written=true" >> "$RUNBOOK_OUTPUT"

log_info "Recorded plan_client_id=${PLAN_CLIENT_ID}, apply_client_id=${APPLY_CLIENT_ID}."
exit 0
