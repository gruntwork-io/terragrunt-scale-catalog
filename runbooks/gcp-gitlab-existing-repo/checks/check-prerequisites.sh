#!/bin/bash
# Verify the local CLI tools this runbook depends on are installed and on PATH.
set -uo pipefail

missing=0
for tool in git mise gcloud jq; do
  if command -v "$tool" >/dev/null 2>&1; then
    log_info "$tool found: $(command -v "$tool")"
  else
    log_error "$tool is not installed or not on your PATH"
    missing=1
  fi
done

# boilerplate normally comes from the Runbooks app, which points scripts at its
# bundled copy via BOILERPLATE_BIN. Older app builds do not, so fall back to
# requiring it on PATH — the generate step uses "${BOILERPLATE_BIN:-boilerplate}".
bp="${BOILERPLATE_BIN:-}"
if [ -n "$bp" ] && { [ -x "$bp" ] || command -v "$bp" >/dev/null 2>&1; }; then
  log_info "boilerplate found: $bp (provided by the Runbooks app)"
elif command -v boilerplate >/dev/null 2>&1; then
  log_info "boilerplate found: $(command -v boilerplate)"
else
  log_error "boilerplate is not available: BOILERPLATE_BIN is unset and boilerplate is not on your PATH"
  log_error "Update the Runbooks app, which bundles boilerplate, or install it: https://github.com/gruntwork-io/boilerplate/releases"
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  log_error "Install the missing tools listed above, then run this check again."
  log_error "git: https://git-scm.com/downloads | mise: https://mise.jdx.dev | gcloud: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

log_info "All prerequisites are installed."
exit 0
