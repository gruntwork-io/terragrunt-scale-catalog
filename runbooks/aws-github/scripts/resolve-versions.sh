#!/bin/bash
# Discover the newest release of everything this bootstrap pins: the terragrunt-scale-catalog
# itself, plus Terragrunt and the two IaC binaries.
#
# Publishes catalog_ref, terragrunt_version, opentofu_version and terraform_version to
# $RUNBOOK_OUTPUT. The generate step uses each one unless you overrode that field in the form
# below, so the defaults track upstream instead of going stale in this file.
#
# Nothing here is fatal: an unresolved value simply leaves the generate step falling back to your
# form input and then to a built-in pin, so being offline never blocks the runbook.
set -uo pipefail

# mise is the tool this runbook already uses to install and pin Terragrunt/OpenTofu/Terraform, so
# its registry is also the right place to ask what the newest version of each one is.
latest_tool_version() {
  tool=$1
  command -v mise >/dev/null 2>&1 || { printf ''; return 0; }
  version=$(mise latest "$tool" 2>/dev/null | tail -1)
  case $version in
    ''|*[!0-9.]*) printf '' ;;
    *) printf '%s' "$version" ;;
  esac
}

log_info "Resolving the latest terragrunt-scale-catalog release tag..."
CATALOG_REF=$(git ls-remote --tags --refs --sort=-v:refname \
  https://github.com/gruntwork-io/terragrunt-scale-catalog.git 'v*' 2>/dev/null \
  | head -1 | sed 's#.*refs/tags/##')

log_info "Resolving the latest Terragrunt, OpenTofu and Terraform releases..."
TERRAGRUNT_VERSION=$(latest_tool_version terragrunt)
OPENTOFU_VERSION=$(latest_tool_version opentofu)
TERRAFORM_VERSION=$(latest_tool_version terraform)

{
  echo "catalog_ref=${CATALOG_REF}"
  echo "terragrunt_version=${TERRAGRUNT_VERSION}"
  echo "opentofu_version=${OPENTOFU_VERSION}"
  echo "terraform_version=${TERRAFORM_VERSION}"
} >> "$RUNBOOK_OUTPUT"

log_info "Catalog release:    ${CATALOG_REF:-<unresolved>}"
log_info "Terragrunt:         ${TERRAGRUNT_VERSION:-<unresolved>}"
log_info "OpenTofu:           ${OPENTOFU_VERSION:-<unresolved>}"
log_info "Terraform:          ${TERRAFORM_VERSION:-<unresolved>}"

if [ -z "$CATALOG_REF" ] || [ -z "$TERRAGRUNT_VERSION" ] || [ -z "$OPENTOFU_VERSION" ] || [ -z "$TERRAFORM_VERSION" ]; then
  log_warn "Some versions could not be resolved (offline?). For those, the generate step uses your"
  log_warn "form value if you changed it, and a built-in pin otherwise."
fi

log_info "Every field below is left on latest by default and takes the value above. Change one only"
log_info "if you need a specific version pinned."
exit 0
