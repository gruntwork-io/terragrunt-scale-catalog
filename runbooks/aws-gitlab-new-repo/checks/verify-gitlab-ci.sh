#!/bin/bash
# Confirm the GitLab CI pipeline was rendered by the infrastructure-live template.
# The infrastructure-live template GENERATES this file, so this check replaces the manual
# workflow-authoring step used for existing repositories.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the new repository' step first."
  exit 1
fi

cd "$REPO_FILES"

if [ -f ".gitlab-ci.yml" ]; then
  log_info "Found .gitlab-ci.yml — the Pipelines GitLab CI pipeline was generated."
  exit 0
else
  log_error "Missing .gitlab-ci.yml. Did the generate step run?"
  exit 1
fi
