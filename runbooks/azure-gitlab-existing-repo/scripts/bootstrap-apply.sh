#!/bin/bash
# Apply the bootstrap stack. This creates real Azure resources (Entra ID applications, service principals,
# federated credentials, custom roles, role assignments) and the state storage account. State remains
# local until the migrate-state step. Review the plan output above before running this.
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
RB_out_bootstrap_plan_planned=$(rb_unquote "{{ .outputs.bootstrap_plan.planned }}")
RB_out_derive_azure_azure_subscription_id=$(rb_unquote "{{ .outputs.derive_azure.azure_subscription_id }}")
RB_out_derive_azure_azure_tenant_id=$(rb_unquote "{{ .outputs.derive_azure.azure_tenant_id }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the plan output gates this block until the plan step has run.
: "${RB_out_bootstrap_plan_planned}"

export ARM_TENANT_ID="${RB_out_derive_azure_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_derive_azure_azure_subscription_id}"

cd "$REPO_FILES/${RB_SubscriptionName}/bootstrap"

log_info "Applying the bootstrap stack (state remains local until migration)..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate apply

echo "applied=true" >> "$RUNBOOK_OUTPUT"

log_info "Bootstrap apply complete. The Entra ID applications and state storage now exist in subscription ${RB_out_derive_azure_azure_subscription_id}."
