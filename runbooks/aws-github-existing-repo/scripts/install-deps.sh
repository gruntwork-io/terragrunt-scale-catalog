#!/bin/bash
# Install the tool dependencies (Terragrunt and OpenTofu) pinned in the repository's mise config.
# boilerplate is a prerequisite you install yourself and is verified in pre-flight — it is NOT installed
# here. Run this AFTER the repository has been generated/cloned so a .mise.toml is present.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

cd "$REPO_FILES"

if [ ! -f .mise.toml ] && [ ! -f mise.toml ] && [ ! -f .config/mise/config.toml ]; then
  # No mise config in the repo (an existing repo not scaffolded from this catalog). Create one matching
  # what the catalog's infrastructure-live template generates for AWS: Terragrunt and OpenTofu from your
  # inputs. (The AWS CLI is a pre-flight prerequisite and is not pinned via mise.)
  log_warn "No mise config found in the repository; pinning Terragrunt and OpenTofu from your inputs."
  mise use "terragrunt@{{ .inputs.TerragruntVersion }}" "opentofu@{{ .inputs.OpenTofuVersion }}"
fi

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
