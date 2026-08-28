#!/bin/bash
# Confirm the plan/apply service accounts created by the bootstrap stack exist in the project.
# References the GCP auth check output so this stays gated until you have authenticated.
set -uo pipefail

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
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_out_gcp_auth_check_gcp_ready=$(rb_unquote "{{ .outputs.gcp_auth_check.gcp_ready }}")

log_info "Verifying service accounts (GCP access ready: ${RB_out_gcp_auth_check_gcp_ready})."

PREFIX="${RB_OIDCResourcePrefix}"
PROJECT_ID="${RB_GCPProjectID}"
rc=0
for sa in "${PREFIX}-plan" "${PREFIX}-apply"; do
  EMAIL="${sa}@${PROJECT_ID}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
    log_info "Service account ${EMAIL} exists."
  else
    log_error "Service account ${EMAIL} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both Pipelines service accounts are present."
fi
exit "$rc"
