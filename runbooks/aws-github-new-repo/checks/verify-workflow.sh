#!/bin/bash
# Confirm the Pipelines GitHub Actions workflows were rendered by the infrastructure-live template.
# The infrastructure-live template GENERATES these workflows, so this check replaces the manual
# workflow-authoring step used for existing repositories.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the new repository' step first."
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

check_file ".github/workflows/pipelines.yml"
check_file ".github/workflows/pipelines-unlock.yml"

if [ "{{ .inputs.IncludeDriftDetection }}" = "true" ]; then
  check_file ".github/workflows/pipelines-drift-detection.yml"
else
  log_info "Drift detection was disabled; skipping the drift-detection workflow check."
fi

if [ "$rc" -eq 0 ]; then
  log_info "The Pipelines GitHub Actions workflows were generated."
fi
exit "$rc"
