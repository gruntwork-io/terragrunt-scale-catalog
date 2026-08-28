#!/bin/bash
# Read the plan/apply application client IDs from the bootstrap stack outputs and write them into
# .gruntwork/environment-<sub>.hcl, replacing the empty FIXME placeholders.
set -euo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and a single pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_out_bootstrap_apply_applied=$(rb_unquote "{{ .outputs.bootstrap_apply.applied }}")
RB_out_derive_azure_azure_subscription_id=$(rb_unquote "{{ .outputs.derive_azure.azure_subscription_id }}")
RB_out_derive_azure_azure_tenant_id=$(rb_unquote "{{ .outputs.derive_azure.azure_tenant_id }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

log_info "Bootstrap applied (${RB_out_bootstrap_apply_applied}). Reading client IDs from stack outputs..."

export ARM_SUBSCRIPTION_ID="${RB_out_derive_azure_azure_subscription_id}"
export ARM_TENANT_ID="${RB_out_derive_azure_azure_tenant_id}"
export ARM_USE_CLI=true

SUB="${RB_SubscriptionName}"
ENV_FILE="$REPO_FILES/.gruntwork/environment-${SUB}.hcl"

cd "$REPO_FILES/${SUB}/bootstrap"

OUTPUTS=$(terragrunt stack output --no-stack-generate --non-interactive -json 2>/dev/null || true)

read_client_id() {
  # $1 = plan_app | apply_app. Outputs may be nested under the stack name ("bootstrap") or at the top
  # level, and client_id may be a raw string or {value,type}-wrapped.
  printf '%s' "$OUTPUTS" | jq -r --arg app "$1" '
    ((.bootstrap[$app] // .[$app]) // {}) as $a
    | ($a.client_id | if type == "object" then .value else . end) // empty
  ' 2>/dev/null
}

PLAN_CLIENT_ID=$(read_client_id plan_app)
APPLY_CLIENT_ID=$(read_client_id apply_app)

if [ -z "$PLAN_CLIENT_ID" ] || [ -z "$APPLY_CLIENT_ID" ]; then
  log_error "Could not read the plan/apply client IDs from the bootstrap outputs."
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  log_error "Environment file ${ENV_FILE} not found."
  exit 1
fi

log_info "Writing client IDs into .gruntwork/environment-${SUB}.hcl ..."
sed -i.bak -E "s|^([[:space:]]*plan_client_id[[:space:]]*=[[:space:]]*)\"\".*$|\1\"${PLAN_CLIENT_ID}\"|" "$ENV_FILE"
sed -i.bak -E "s|^([[:space:]]*apply_client_id[[:space:]]*=[[:space:]]*)\"\".*$|\1\"${APPLY_CLIENT_ID}\"|" "$ENV_FILE"
rm -f "${ENV_FILE}.bak"

{
  echo "plan_client_id=${PLAN_CLIENT_ID}"
  echo "apply_client_id=${APPLY_CLIENT_ID}"
  echo "client_ids_written=true"
} >>"$RUNBOOK_OUTPUT"

log_info "Recorded plan client ID ${PLAN_CLIENT_ID} and apply client ID ${APPLY_CLIENT_ID}."
exit 0
