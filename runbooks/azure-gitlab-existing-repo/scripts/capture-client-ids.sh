#!/bin/bash
# Read the plan/apply application client IDs from the applied bootstrap stack and write them into
# .gruntwork/environment-<SubscriptionName>.hcl, replacing the FIXME placeholders. This runs before the
# remote backend is enabled, so the outputs are read from the local bootstrap state.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the apply output gates this block until the bootstrap apply step has run.
: "{{ .outputs.bootstrap_apply.applied }}"

export ARM_TENANT_ID="{{ .outputs.derive_azure.azure_tenant_id }}"
export ARM_SUBSCRIPTION_ID="{{ .outputs.derive_azure.azure_subscription_id }}"

BOOTSTRAP_DIR="$REPO_FILES/{{ .inputs.SubscriptionName }}/bootstrap"
ENV_HCL="$REPO_FILES/.gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl"

cd "$BOOTSTRAP_DIR"

# Locate the generated plan/apply application units by their stack paths, regardless of nesting depth.
# Each is a leaf Terragrunt unit (has a terragrunt.hcl) exposing a `client_id` output.
find_app_dir() {
  local suffix="$1" d
  while IFS= read -r d; do
    if [ -f "$d/terragrunt.hcl" ]; then
      echo "$d"
      return 0
    fi
  done < <(find .terragrunt-stack -type d -path "*/${suffix}" 2>/dev/null)
  return 1
}

PLAN_APP_DIR="$(find_app_dir 'oidc/plan/app' || true)"
APPLY_APP_DIR="$(find_app_dir 'oidc/apply/app' || true)"

if [ -z "$PLAN_APP_DIR" ] || [ -z "$APPLY_APP_DIR" ]; then
  log_error "Could not locate the generated plan/apply application units under .terragrunt-stack."
  log_error "Make sure the bootstrap apply step completed successfully."
  exit 1
fi

log_info "Reading client IDs from the applied bootstrap outputs..."
PLAN_CLIENT_ID="$(cd "$PLAN_APP_DIR" && terragrunt output --non-interactive -raw client_id)"
APPLY_CLIENT_ID="$(cd "$APPLY_APP_DIR" && terragrunt output --non-interactive -raw client_id)"

if [ -z "$PLAN_CLIENT_ID" ] || [ -z "$APPLY_CLIENT_ID" ]; then
  log_error "Failed to read one or both client IDs from the bootstrap outputs."
  exit 1
fi

if [ ! -f "$ENV_HCL" ]; then
  log_error "Environment config not found at ${ENV_HCL}. Did the generate step run?"
  exit 1
fi

log_info "Writing client IDs into $(basename "$ENV_HCL")..."
sed -i.bak \
  -e "s|plan_client_id[[:space:]]*=.*|plan_client_id  = \"${PLAN_CLIENT_ID}\"|" \
  -e "s|apply_client_id[[:space:]]*=.*|apply_client_id = \"${APPLY_CLIENT_ID}\"|" \
  "$ENV_HCL"
rm -f "${ENV_HCL}.bak"

{
  echo "plan_client_id=${PLAN_CLIENT_ID}"
  echo "apply_client_id=${APPLY_CLIENT_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Captured plan client ID ${PLAN_CLIENT_ID} and apply client ID ${APPLY_CLIENT_ID}."
exit 0
