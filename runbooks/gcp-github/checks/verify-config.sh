#!/bin/bash
# Verify the expected Pipelines configuration files were generated in the repository.
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

RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
RB_out_inspect_repository_repo_mode=$(rb_unquote "{{ .outputs.inspect_repository.repo_mode }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

cd "$REPO_FILES"
rc=0

check_file() {
  if [ -f "$1" ]; then
    log_info "Found $1"
  else
    log_error "Missing $1"
    rc=1
  fi
}

if [ "$RB_out_inspect_repository_repo_mode" = "scaffold" ]; then
  check_file "root.hcl"
  check_file ".mise.toml"
fi
check_file ".github/workflows/pipelines.yml"
check_file ".gruntwork/repository.hcl"
check_file ".gruntwork/environment-${RB_ProjectName}.hcl"
check_file "${RB_ProjectName}/project.hcl"
check_file "${RB_ProjectName}/bootstrap/terragrunt.stack.hcl"

if [ "$rc" -eq 0 ]; then
  log_info "All expected Pipelines configuration files are present."
fi
exit "$rc"
