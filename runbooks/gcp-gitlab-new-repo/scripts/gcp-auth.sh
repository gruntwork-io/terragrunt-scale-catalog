#!/bin/bash
# Authenticate to GCP with the gcloud CLI. There is no dedicated GCP auth block, so we drive gcloud
# directly: log the user in, update Application Default Credentials (used by Terragrunt/OpenTofu's
# Google provider), and set the active project. Login opens a browser to complete the flow.
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

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")

PROJECT_ID="${RB_GCPProjectID}"

log_info "Logging in to gcloud and updating Application Default Credentials (a browser window will open)..."
gcloud auth login --update-adc

log_info "Setting the active project to ${PROJECT_ID}..."
gcloud config set project "$PROJECT_ID"

# Set the ADC quota/billing project so client libraries (and OpenTofu) don't warn about an unset one.
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null 2>&1 \
  || log_warn "Could not set the ADC quota project; continuing (this is usually harmless)."

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)

{
  echo "gcp_account=${ACTIVE_ACCOUNT}"
  echo "gcp_project_id=${PROJECT_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info "Authenticated to GCP as ${ACTIVE_ACCOUNT} (project ${PROJECT_ID})."
exit 0
