#!/bin/bash
# Resolve the latest terragrunt-scale-catalog release tag so the bootstrap pins the newest version by
# default. Writes catalog_ref to $RUNBOOK_OUTPUT for the generate step to consume. If resolution fails
# (e.g. no network), the generate step falls back to your TerragruntScaleCatalogRef input, then to a
# built-in pinned default — so this step never blocks the runbook.
set -uo pipefail

log_info "Resolving the latest terragrunt-scale-catalog release tag..."
LATEST=$(git ls-remote --tags --refs --sort=-v:refname \
  https://github.com/gruntwork-io/terragrunt-scale-catalog.git 'v*' 2>/dev/null \
  | head -1 | sed 's#.*refs/tags/##')

if [ -z "$LATEST" ]; then
  log_warn "Could not resolve the latest release tag (offline?). The generate step will use your"
  log_warn "TerragruntScaleCatalogRef input if set, or a built-in fallback otherwise."
fi

echo "catalog_ref=${LATEST}" >> "$RUNBOOK_OUTPUT"
log_info "Latest catalog release: ${LATEST:-<unresolved>}"
exit 0
