#!/bin/bash
# Install the tool dependencies (Terragrunt, OpenTofu, and the Google Cloud CLI) pinned in the
# repository's mise config. boilerplate is a prerequisite you install yourself and is verified in
# pre-flight — it is NOT installed here. Run this AFTER the repository has been generated/cloned so a
# .mise.toml is present.
set -euo pipefail

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
  mise use "terragrunt@{{ .inputs.TerragruntVersion }}" "opentofu@{{ .inputs.OpenTofuVersion }}" "gcloud@565.0.0"
fi

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
