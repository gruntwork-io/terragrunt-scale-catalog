#!/bin/bash
# Verify the local CLI tools this runbook depends on are installed and on PATH.
set -uo pipefail

missing=0
for tool in git mise boilerplate az glab jq; do
  if command -v "$tool" >/dev/null 2>&1; then
    log_info "$tool found: $(command -v "$tool")"
  else
    log_error "$tool is not installed or not on your PATH"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  log_error "Install the missing tools listed above, then run this check again."
  log_error "git: https://git-scm.com/downloads | mise: https://mise.jdx.dev | az: https://learn.microsoft.com/cli/azure/install-azure-cli | glab: https://gitlab.com/gitlab-org/cli"
  exit 1
fi

log_info "All prerequisites are installed."
exit 0
