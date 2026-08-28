#!/bin/bash
# Verify the expected Pipelines configuration files were generated, and that the plan/apply
# client IDs were filled into the environment file (no empty FIXME placeholders remain).
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

cd "$REPO_FILES"
SUB="${RB_SubscriptionName}"
rc=0

check_file() {
  if [ -f "$1" ]; then
    log_info "Found $1"
  else
    log_error "Missing $1"
    rc=1
  fi
}

check_file "root.hcl"
check_file ".gitlab-ci.yml"
check_file ".gruntwork/environment-${SUB}.hcl"
check_file "${SUB}/bootstrap/terragrunt.stack.hcl"

# The .gitlab-ci.yml must be generated for GitLab CI to run Pipelines.
if [ -f ".gitlab-ci.yml" ]; then
  log_info ".gitlab-ci.yml was generated (GitLab CI will run Pipelines)."
fi

# Confirm the client IDs are no longer the empty FIXME placeholders.
ENV_FILE=".gruntwork/environment-${SUB}.hcl"
if [ -f "$ENV_FILE" ]; then
  if grep -Eq 'plan_client_id[[:space:]]*=[[:space:]]*""' "$ENV_FILE" ||
    grep -Eq 'apply_client_id[[:space:]]*=[[:space:]]*""' "$ENV_FILE"; then
    log_error "One or more client IDs in ${ENV_FILE} are still empty. Re-run 'Record the OIDC client IDs'."
    rc=1
  else
    log_info "plan_client_id and apply_client_id are populated in ${ENV_FILE}."
  fi
fi

if [ "$rc" -eq 0 ]; then
  log_info "All expected Pipelines configuration files are present and populated."
fi
exit "$rc"
