#!/bin/bash
# Install the tool dependencies (Terragrunt and the chosen IaC binary) pinned in the repo's mise config.
# boilerplate is a prerequisite you install yourself and is verified in pre-flight — it is NOT installed
# here. Run this AFTER the repository has been generated/cloned so a .mise.toml is present.
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

RB_IaCTool=$(rb_unquote "{{ .inputs.IaCTool }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_TerraformVersion=$(rb_unquote "{{ .inputs.TerraformVersion }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

cd "$REPO_FILES"

if [ ! -f .mise.toml ] && [ ! -f mise.toml ] && [ ! -f .config/mise/config.toml ]; then
  # No mise config in the repo (an existing repo not scaffolded from this catalog). Create one
  # matching what the catalog's infrastructure-live template generates for AWS. The AWS CLI is a
  # pre-flight prerequisite and is not pinned via mise.
  #
  # Which IaC binary to pin follows the same authority as the generate step: a tf_binary already
  # committed to this repository wins over the form, because that is what Pipelines will run.
  # Without this, an existing repo carrying tf_binary = "terraform" but no mise config would be
  # pinned to OpenTofu here, and CI would install one binary and then run the other.
  TOOL="$RB_IaCTool"
  if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
    recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
    if [ -n "$recorded" ] && [ "$recorded" != "$TOOL" ]; then
      log_warn "This repository records tf_binary = \"${recorded}\"; pinning ${recorded} rather than ${TOOL}."
      TOOL="$recorded"
    fi
  fi

  if [ "$TOOL" = "terraform" ]; then
    log_warn "No mise config found in the repository; pinning Terragrunt and Terraform."
    mise use "terragrunt@${RB_TerragruntVersion}" "terraform@${RB_TerraformVersion}"
  else
    log_warn "No mise config found in the repository; pinning Terragrunt and OpenTofu."
    mise use "terragrunt@${RB_TerragruntVersion}" "opentofu@${RB_OpenTofuVersion}"
  fi
fi

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
