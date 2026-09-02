#!/bin/bash
# Capture the plan/apply Entra ID application client IDs from the bootstrap stack outputs and write them
# into .gruntwork/environment-<sub>.hcl automatically, replacing the empty FIXME placeholders. This
# removes the manual copy/paste step from the docs.
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
RB_out_read_details_azure_subscription_id=$(rb_unquote "{{ .outputs.read_details.azure_subscription_id }}")
RB_out_read_details_azure_tenant_id=$(rb_unquote "{{ .outputs.read_details.azure_tenant_id }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

SUB="${RB_SubscriptionName}"
ENV_HCL="$REPO_FILES/.gruntwork/environment-${SUB}.hcl"

if [ ! -f "$ENV_HCL" ]; then
  log_error "Expected environment file not found: ${ENV_HCL}"
  exit 1
fi

export ARM_TENANT_ID="${RB_out_read_details_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_read_details_azure_subscription_id}"

cd "$REPO_FILES/${SUB}/bootstrap"

log_info "Reading bootstrap stack outputs..."
OUT_JSON=$(terragrunt stack output -json 2>/dev/null || true)

if [ -z "$OUT_JSON" ]; then
  log_error "Could not read 'terragrunt stack output -json'. Did the apply step succeed?"
  exit 1
fi

extract_client_id() {
  # $1 = plan_app | apply_app. Handles outputs nested under the stack name ("bootstrap") or at the top
  # level, and client_id values that are raw strings or {value,type}-wrapped.
  jq -r --arg app "$1" '
    ((.bootstrap[$app] // .[$app]) // {}) as $a
    | ($a.client_id | if type == "object" then .value else . end) // empty
  ' <<<"$OUT_JSON"
}

PLAN_CLIENT_ID=$(extract_client_id plan_app)
APPLY_CLIENT_ID=$(extract_client_id apply_app)

if [ -z "$PLAN_CLIENT_ID" ] || [ -z "$APPLY_CLIENT_ID" ]; then
  log_error "Could not extract plan/apply client IDs from the stack outputs."
  log_error "Inspect 'terragrunt stack output' in ${SUB}/bootstrap and fill in the client IDs manually."
  exit 1
fi

log_info "Writing client IDs into ${ENV_HCL} ..."
sed -E \
  -e "s|(plan_client_id[[:space:]]*=[[:space:]]*)\"\".*|\1\"${PLAN_CLIENT_ID}\"|" \
  -e "s|(apply_client_id[[:space:]]*=[[:space:]]*)\"\".*|\1\"${APPLY_CLIENT_ID}\"|" \
  "$ENV_HCL" > "$ENV_HCL.tmp"
mv "$ENV_HCL.tmp" "$ENV_HCL"

{
  echo "plan_client_id=${PLAN_CLIENT_ID}"
  echo "apply_client_id=${APPLY_CLIENT_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Recorded plan_client_id=${PLAN_CLIENT_ID} and apply_client_id=${APPLY_CLIENT_ID}."
exit 0
