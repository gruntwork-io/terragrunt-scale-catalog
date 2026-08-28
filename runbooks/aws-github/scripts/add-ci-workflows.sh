#!/bin/bash
# Write the Gruntwork Pipelines GitHub Actions workflows (plan/apply, unlock, drift-detection) into the
# repository. Each file is written only if it does NOT already exist, so bootstrapping an ADDITIONAL
# account into a repo that already has Pipelines will not overwrite (or revert customizations to) its
# workflows. Set OverwriteWorkflows=true to force-refresh them to the catalog's standard versions.
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

RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_OverwriteWorkflows=$(rb_unquote "{{ .inputs.OverwriteWorkflows }}")
RB_out_inspect_repository_repo_mode=$(rb_unquote "{{ .outputs.inspect_repository.repo_mode }}")
RB_repo_mode="${RB_out_inspect_repository_repo_mode}"

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

if [ "$RB_repo_mode" = "scaffold" ]; then
  log_info "The repository scaffold already rendered the Pipelines workflows; nothing to add."
  exit 0
fi

OVERWRITE="${RB_OverwriteWorkflows}"
WF_DIR="$REPO_FILES/.github/workflows"
mkdir -p "$WF_DIR"

# Returns 0 (write) when the file is absent, or when OverwriteWorkflows is true; returns 1 (skip) when the
# file already exists and overwrite was not requested.
should_write() {
  local dest="$WF_DIR/$1"
  if [ -f "$dest" ] && [ "$OVERWRITE" != "true" ]; then
    log_warn "Skipping $1: it already exists (set OverwriteWorkflows=true to replace it)."
    return 1
  fi
  return 0
}

if should_write pipelines.yml; then
  cat > "$WF_DIR/pipelines.yml" <<'WORKFLOWEOF'
name: Pipelines
run-name: "[GWP]: ${{ "{{" }} github.event.commits[0].message || github.event.pull_request.title || 'No commit message' {{ "}}" }}"
on:
  push:
    branches:
      - "__RB_DeployBranch__"
    paths-ignore:
      - ".github/**"
  pull_request:
    types:
      - opened
      - synchronize
      - reopened
    paths-ignore:
      - ".github/**"

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines.yml@v4
WORKFLOWEOF
  sed -i.bak "s|__RB_DeployBranch__|${RB_DeployBranch}|g" "$WF_DIR/pipelines.yml"
  rm -f "$WF_DIR/pipelines.yml.bak"
  log_info "Wrote .github/workflows/pipelines.yml"
fi

if should_write pipelines-unlock.yml; then
  cat > "$WF_DIR/pipelines-unlock.yml" <<'WORKFLOWEOF'
# Gruntwork Pipelines Unlock Workflow. Manually unlock a state file left locked by a cancelled or crashed run.
# Trigger from Actions, Pipelines Unlock, Run workflow. Docs: https://docs.gruntwork.io/2.0/docs/pipelines/guides/unlocking-state

name: Pipelines Unlock
run-name: "[GWP]: Pipelines Unlock"
on:
  workflow_dispatch:
    inputs:
      lock_id:
        description: "The ID of the lock, usually a GUID. This is generally found in the console output when Terraform/OpenTofu command fails due to a timeout waiting to acquire a lock. (required if not running unlock_all)"
        required: false
        type: string
      unit_path:
        description: "Path to the Terragrunt Unit directory where the lock is held (everything up to but not including terragrunt.hcl - required if not running unlock_all)"
        required: false
        type: string
      stack_path:
        description: "Path to a Terragrunt Stack directory (everything up to but not including terragrunt.stack.hcl) that generates content required to run unlock in a specified Terragrunt Unit"
        required: false
        type: string
      unlock_all:
        description: "Forcibly reset all locks by deleting the dynamodb table"
        required: false
        type: boolean

permissions:
  id-token: write # Required to assume OIDC roles and create pull requests
  actions: read # Required to manage artifacts via REST API

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-unlock.yml@v4
    with:
      lock_id: ${{ "{{" }} inputs.lock_id {{ "}}" }}
      unit_path: ${{ "{{" }} inputs.unit_path {{ "}}" }}
      unlock_all: ${{ "{{" }} inputs.unlock_all {{ "}}" }}
      stack_path: ${{ "{{" }} inputs.stack_path {{ "}}" }}
WORKFLOWEOF
  log_info "Wrote .github/workflows/pipelines-unlock.yml"
fi

if should_write pipelines-drift-detection.yml; then
  cat > "$WF_DIR/pipelines-drift-detection.yml" <<'WORKFLOWEOF'
# Gruntwork Pipelines Drift Detection workflow. Runs `terragrunt plan` across units and opens PRs for any drift found.
# Enable scheduled runs by uncommenting the cron below. Docs: https://docs.gruntwork.io/2.0/docs/pipelines/guides/running-drift-detection

name: Pipelines Drift Detection
run-name: "[GWP]: Pipelines Drift Detection"
on:
  # Uncomment to enable scheduled Drift Detection
  # schedule:
  #  - cron: '15 12 * * 1'
  workflow_dispatch:
    inputs:
      pipelines_drift_detection_filter:
        description: Limit drift detection to units matching filter https://docs.gruntwork.io/2.0/docs/pipelines/guides/running-drift-detection#drift-detection-filter
        type: string
      pipelines_drift_detection_branch:
        description: The branch name used for drift remediation PRs
        default: drift-detection
        type: string

permissions:
  id-token: write # Required to assume OIDC roles when using default GITHUB_TOKEN
  actions: read # Required to manage artifacts via REST API when using default GITHUB_TOKEN

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-drift-detection.yml@v4
    with:
      pipelines_drift_detection_filter: ${{ "{{" }} inputs.pipelines_drift_detection_filter {{ "}}" }}
      pipelines_drift_detection_branch: ${{ "{{" }} inputs.pipelines_drift_detection_branch {{ "}}" }}
WORKFLOWEOF
  log_info "Wrote .github/workflows/pipelines-drift-detection.yml"
fi

log_info "CI workflow setup complete."
