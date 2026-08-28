#!/bin/bash
# Confirm the plan/apply Entra ID applications created by the bootstrap stack exist in the tenant.
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

RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")

PREFIX="${RB_OIDCResourcePrefix}"
rc=0
for app in "${PREFIX}-plan" "${PREFIX}-apply"; do
  APP_ID=$(az ad app list --display-name "$app" --query "[0].appId" -o tsv 2>/dev/null || true)
  if [ -n "$APP_ID" ]; then
    log_info "Entra ID application ${app} exists (appId ${APP_ID})."
  else
    log_error "Entra ID application ${app} not found. Did the bootstrap apply step succeed?"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC Entra ID applications are present."
fi
exit "$rc"
