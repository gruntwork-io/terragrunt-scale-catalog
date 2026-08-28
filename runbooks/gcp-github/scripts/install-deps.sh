#!/bin/bash
# Install the tool dependencies (Terragrunt, OpenTofu, and the Google Cloud CLI) pinned in the
# repository's mise config. boilerplate is a prerequisite you install yourself and is verified in
# pre-flight — it is NOT installed here. Run this AFTER the repository has been generated/cloned so a
# .mise.toml is present.
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

RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

cd "$REPO_FILES"

if [ ! -f .mise.toml ] && [ ! -f mise.toml ] && [ ! -f .config/mise/config.toml ]; then
  # No mise config in the repo (an existing repo not scaffolded from this catalog). Create one matching
  # what the catalog's infrastructure-live template generates for GCP: Terragrunt and OpenTofu from your
  # inputs, plus the Google Cloud CLI pinned to the catalog default version.
  log_warn "No mise config found in the repository; pinning Terragrunt, OpenTofu, and gcloud."
  # A repository can already record which binary Pipelines will run. Honour it over the form,
  # or CI installs one binary and runs the other.
  IAC_PIN="opentofu@${RB_OpenTofuVersion}"
  if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
    recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
    case "$recorded" in
      terraform) IAC_PIN="terraform@1.15.9"; log_warn "This repository records tf_binary = \"terraform\"; pinning Terraform." ;;
      opentofu)  IAC_PIN="opentofu@${RB_OpenTofuVersion}" ;;
    esac
  fi
  mise use "terragrunt@${RB_TerragruntVersion}" "$IAC_PIN" "gcloud@565.0.0"
fi

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
