#!/bin/bash
# Confirm the plan/apply client IDs were written into the environment HCL (no empty FIXME values left).
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

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

ENV_HCL="$REPO_FILES/.gruntwork/environment-${RB_SubscriptionName}.hcl"
if [ ! -f "$ENV_HCL" ]; then
  log_error "Missing ${ENV_HCL}"
  exit 1
fi

rc=0
for key in plan_client_id apply_client_id; do
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$ENV_HCL" || true)
  if [ -z "$line" ]; then
    log_error "No ${key} entry found in the environment HCL."
    rc=1
  elif echo "$line" | grep -qE '=[[:space:]]*""'; then
    log_error "${key} is still empty. Did the 'Record the plan/apply client IDs' step run?"
    rc=1
  else
    log_info "${key} is set."
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC client IDs are populated in the environment HCL."
fi
exit "$rc"
