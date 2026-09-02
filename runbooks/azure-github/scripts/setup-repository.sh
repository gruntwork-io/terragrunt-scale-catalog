#!/bin/bash
# Set up the repository in one pass: render the Terragrunt Scale configuration, install the tool
# versions it pins, add the Pipelines CI workflows, and write the README.
#
# These were four separate blocks. They are one script because each depends on the one before it and
# there is no useful place to stop in between — and because the Runbooks app renders template
# variables only into the script a block points at, so a wrapper cannot call the four in turn.
#
# Each phase runs in a subshell, so its own `cd`, `set` and `exit` stay local to it. A phase that
# fails stops the run and names itself, and the phases before it have already done their work: fix
# the problem and run the step again.
set -euo pipefail

# Banner, folded in from logo.sh. Printed to stdout rather than stderr: nothing here is an error,
# and when a block runs without a PTY the app reads stdout and stderr as two separate streams, so a
# stderr banner can land after the first few log lines instead of at the top.
logo() {
  # 256-colour purple (xterm 93, #8700ff) rather than the basic 16-colour palette, whose only purple
  # is magenta. Rendered by the app through ansi-to-react, and by any 256-colour terminal in
  # instruction mode.
  printf "\033[38;5;93m"
  cat <<'LOGOEOF'

████████╗███████╗██████╗ ██████╗  █████╗  ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║   ██║████╗  ██║╚══██╔══╝
   ██║   █████╗  ██████╔╝██████╔╝███████║██║  ███╗██████╔╝██║   ██║██╔██╗ ██║   ██║
   ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║
   ██║   ███████╗██║  ██║██║  ██║██║  ██║╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║   ██║
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝
                                                                           ▄▄▄
                    ███████╗ ██████╗ █████╗ ██╗     ███████╗             ▄▀░░░▀▄
                    ██╔════╝██╔════╝██╔══██╗██║     ██╔════╝           ▄▀░░░░░░░▀▄
                    ███████╗██║     ███████║██║     █████╗           ▄▀░░░░░░░░░░░▀▄
                    ╚════██║██║     ██╔══██║██║     ██╔══╝           █▀▄░░░░░░░░░▄▀█
                    ███████║╚██████╗██║  ██║███████╗███████╗         █▓▓▀▄░░░░░▄▀▒▒█
                    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝         █▓▓▓▓▀▄▄▄▀▒▒▒▒█
By Gruntwork                                                          ▀▄▓▓▓▓█▒▒▒▒▄▀
                                                                        ▀▄▓▓█▒▒▄▀
                                                                          ▀▄█▄▀


LOGOEOF
  printf "\033[0m"
}

logo


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

RB_AzureLocation=$(rb_unquote "{{ .inputs.AzureLocation }}")
RB_DeployBranch=$(rb_unquote "{{ .outputs.read_details.deploy_branch }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_IaCTool=$(rb_unquote "{{ .inputs.IaCTool }}")
RB_TerraformVersion=$(rb_unquote "{{ .inputs.TerraformVersion }}")
RB_Issuer=$(rb_unquote "{{ .inputs.Issuer }}")
if [ "$RB_Issuer" = "default" ]; then RB_Issuer=""; fi
RB_out_read_details_repo_mode=$(rb_unquote "{{ .outputs.read_details.repo_mode }}")
RB_StateResourceGroupName=$(rb_unquote "{{ .inputs.StateResourceGroupName }}")
RB_StateStorageAccountName=$(rb_unquote "{{ .inputs.StateStorageAccountName }}")
RB_StateStorageContainerName=$(rb_unquote "{{ .inputs.StateStorageContainerName }}")
RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_out_clone_org_id=$(rb_unquote "{{ .outputs.clone.org_id }}")
RB_out_clone_repo_id=$(rb_unquote "{{ .outputs.clone.repo_id }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")
RB_out_read_details_azure_subscription_id=$(rb_unquote "{{ .outputs.read_details.azure_subscription_id }}")
RB_out_read_details_azure_tenant_id=$(rb_unquote "{{ .outputs.read_details.azure_tenant_id }}")
RB_out_resolve_versions_catalog_ref=$(rb_unquote "{{ .outputs.resolve_versions.catalog_ref }}")
RB_out_resolve_versions_opentofu_version=$(rb_unquote "{{ .outputs.resolve_versions.opentofu_version }}")
RB_out_resolve_versions_terraform_version=$(rb_unquote "{{ .outputs.resolve_versions.terraform_version }}")
RB_out_resolve_versions_terragrunt_version=$(rb_unquote "{{ .outputs.resolve_versions.terragrunt_version }}")
RB_OverwriteWorkflows=$(rb_unquote "{{ .inputs.OverwriteWorkflows }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

cd "$REPO_FILES"

MODE="${RB_out_read_details_repo_mode}"
case "$MODE" in
  scaffold)             TEMPLATE="infrastructure-live" ;;
  account|subscription) MODE="subscription"; TEMPLATE="subscription" ;;
  *) log_error "Unknown repository mode [${MODE}]. Re-run the repository check in step 4."; exit 1 ;;
esac

# Everything this bootstrap pins is decided the same way, in order of authority:
#   1. an explicit override typed (or selected) in the form;
#   2. the newest release discovered by the resolve step;
#   3. a known-good built-in pin, so an offline run still produces a working repository.
# "latest" is each field's default: a non-empty sentinel, because a blank optional input leaves the
# whole block waiting on an unmet dependency and it can never be run.
# The result comes back in $PICKED rather than on stdout: the runbook log helpers write to stdout,
# so capturing this function with $(...) would fold its own log line into the value it returns.
PICKED=""
pick_version() {
  label=$1; from_form=$2; resolved=$3; fallback=$4
  if [ -n "$from_form" ] && [ "$from_form" != "latest" ]; then
    PICKED="$from_form"
    log_info "${label}: ${PICKED} (pinned in the form)"
  elif [ -n "$resolved" ]; then
    PICKED="$resolved"
    log_info "${label}: ${PICKED} (newest release)"
  else
    PICKED="$fallback"
    log_warn "${label}: ${PICKED} (could not resolve the newest release; using the built-in pin)"
  fi
}

pick_version "terragrunt-scale-catalog" \
  "$RB_TerragruntScaleCatalogRef" "$RB_out_resolve_versions_catalog_ref" "v1.13.1"
CATALOG_REF="$PICKED"

pick_version "Terragrunt" \
  "$RB_TerragruntVersion" "$RB_out_resolve_versions_terragrunt_version" "1.0.0"
TERRAGRUNT_VERSION="$PICKED"

pick_version "OpenTofu" \
  "$RB_OpenTofuVersion" "$RB_out_resolve_versions_opentofu_version" "1.11.5"
OPENTOFU_VERSION="$PICKED"

pick_version "Terraform" \
  "$RB_TerraformVersion" "$RB_out_resolve_versions_terraform_version" "1.15.9"
TERRAFORM_VERSION="$PICKED"

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

# --- Render the Terragrunt Scale configuration -------------------
phase_generate() (
# The variable file is written OUTSIDE the repository. It used to be created at the repo root and
# deleted after a successful render, which meant a failed render left it behind — and the pull
# request step stages with `git add -A`, so the leftover would be committed. A temp file cannot be
# committed, and the trap removes it whichever way this phase exits.
VARS_FILE="$(mktemp -d)/vars.yml"
trap 'rm -rf "$(dirname "$VARS_FILE")"' EXIT

# Clear out a vars.yml left in the repo by an older run of this runbook. Matched on the key only
# this template writes, so a file of the user's own with that name is never touched.
if [ -f vars.yml ] && grep -q '^TerragruntScaleCatalogRef:' vars.yml; then
  rm -f vars.yml
  log_info "Removed a vars.yml left in the repository by an earlier run."
fi

log_info "Writing vars.yml for the azure/github/${TEMPLATE} template..."
cat > "$VARS_FILE" <<EOF
SubscriptionName: "${RB_SubscriptionName}"
GitHubOrgName: "${RB_out_clone_repo_owner}"
GitHubRepoName: "${RB_out_clone_repo_name}"
GitHubOrgID: "${RB_out_clone_org_id}"
GitHubRepoID: "${RB_out_clone_repo_id}"
DeployBranch: "${RB_DeployBranch}"
AzureLocation: "${RB_AzureLocation}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
AzureTenantID: "${RB_out_read_details_azure_tenant_id}"
AzureSubscriptionID: "${RB_out_read_details_azure_subscription_id}"
StateResourceGroupName: "${RB_StateResourceGroupName}"
StateStorageAccountName: "${RB_StateStorageAccountName}"
StateStorageContainerName: "${RB_StateStorageContainerName}"
EOF

# Only the full-repository template renders .mise.toml and the CI workflows, so only it takes the
# tool versions, the drift-detection switch, the issuer override and the IaC tool choice.
if [ "$MODE" = "scaffold" ]; then
  cat >> "$VARS_FILE" <<EOF
IncludeDriftDetection: ${RB_IncludeDriftDetection}
TerragruntVersion: "${TERRAGRUNT_VERSION}"
OpenTofuVersion: "${OPENTOFU_VERSION}"
IaCTool: "${RB_IaCTool}"
TerraformVersion: "${TERRAFORM_VERSION}"
EOF
  [ -n "$RB_Issuer" ] && echo "Issuer: \"${RB_Issuer}\"" >> "$VARS_FILE"
fi

log_info "Rendering azure/github/${TEMPLATE} template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/github/${TEMPLATE}?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file "$VARS_FILE" \
  --non-interactive


if [ "$MODE" = "scaffold" ]; then
  log_info "Scaffolded the repository for subscription ${RB_SubscriptionName}."
  exit 0
fi

# From here on: adding a subscription to a repository that already had root.hcl.

# Existing repos may not already ignore Terragrunt's local caches; make sure we never commit them.
touch .gitignore
grep -qxF '.terragrunt-cache' .gitignore || echo '.terragrunt-cache' >> .gitignore
grep -qxF '.terragrunt-stack' .gitignore || echo '.terragrunt-stack' >> .gitignore

log_info "Generated ${RB_SubscriptionName}/bootstrap/, ${RB_SubscriptionName}/sub.hcl, and .gruntwork/environment-${RB_SubscriptionName}.hcl"

# Ensure the repository-wide Gruntwork Pipelines config exists. The account/project/subscription template
# does NOT create .gruntwork/repository.hcl (only infrastructure-live does), so an existing repo adopting
# Pipelines needs it here. Written only if absent, so bootstrapping another account into a repo that
# already has Pipelines will not clobber (or revert customizations to) its repository.hcl.
REPO_HCL="$REPO_FILES/.gruntwork/repository.hcl"
if [ -f "$REPO_HCL" ]; then
  log_info ".gruntwork/repository.hcl already exists; leaving it unchanged."
else
  mkdir -p "$REPO_FILES/.gruntwork"
  cat > "$REPO_HCL" <<'REPOEOF'
// Gruntwork Pipelines repository-wide configuration.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

repository {
  // Commits on this branch trigger `terragrunt apply`. PRs against it trigger `terragrunt plan`.
  // If you change this, also update the branch trigger in your CI workflow file.
  deploy_branch_name = "__RB_DeployBranch__"

  // Controls whether each push creates a new status comment or updates the existing one in-place.
  status_update {
    new_comment_per_push = false
  }

  env {
    PIPELINES_FEATURE_EXPERIMENT_IGNORE_UNITS_WITHOUT_ENVIRONMENT = "true"
  }
}
REPOEOF
  sed -i.bak "s|__RB_DeployBranch__|${RB_DeployBranch}|g" "$REPO_HCL"
  rm -f "$REPO_HCL.bak"
  log_info "Wrote .gruntwork/repository.hcl (deploy branch: ${RB_DeployBranch})"
fi

# Publish the versions this run settled on. Nothing downstream needs them any more — the install
# phase below reads the same variables directly — but they are the record of what was pinned.
{
  echo "catalog_ref=${CATALOG_REF}"
  echo "terragrunt_version=${TERRAGRUNT_VERSION}"
  echo "opentofu_version=${OPENTOFU_VERSION}"
  echo "terraform_version=${TERRAFORM_VERSION}"
} >> "$RUNBOOK_OUTPUT"

exit 0
)

# --- Ensure root.hcl is present ----------------------------------
phase_ensure_root_hcl() (
if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

if [ "$RB_out_read_details_repo_mode" = "scaffold" ]; then
  log_info "The repository scaffold already rendered root.hcl; nothing to ensure."
  exit 0
fi

ROOT_HCL="$REPO_FILES/root.hcl"

if [ -f "$ROOT_HCL" ] && grep -q 'remote_state' "$ROOT_HCL"; then
  log_info "root.hcl already contains a remote_state block; leaving it unchanged."
  exit 0
fi

if [ -f "$ROOT_HCL" ] && [ -s "$ROOT_HCL" ]; then
  log_warn "root.hcl exists but has no remote_state block. Appending the Azure root configuration."
  log_warn "Review root.hcl afterwards for any duplicate locals/generate blocks."
  printf '\n' >> "$ROOT_HCL"
else
  log_info "Creating root.hcl with the Azure root configuration."
fi

cat >> "$ROOT_HCL" <<'ROOT_HCL_EOF'
// Root Terragrunt config included by every unit via `find_in_parent_folders("root.hcl")`.
// Generates the Azure provider for all units. Remote state is commented out until after bootstrap.
// Docs: https://docs.terragrunt.com/reference/config-blocks-and-attributes/#remote_state

// Read environment-level config from the nearest parent files.
locals {
  sub_hcl = read_terragrunt_config(find_in_parent_folders("sub.hcl"))

  state_resource_group_name    = local.sub_hcl.locals.state_resource_group_name
  state_storage_account_name   = local.sub_hcl.locals.state_storage_account_name
  state_storage_container_name = local.sub_hcl.locals.state_storage_container_name
}

# FIXME: Uncomment the code below when you've successfully bootstrapped Pipelines state.
#
# remote_state {
#   backend = "azurerm"
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite"
#   }
#   config = {
#     resource_group_name  = local.state_resource_group_name
#     storage_account_name = local.state_storage_account_name
#     container_name       = local.state_storage_container_name
#     key                  = "${path_relative_to_include()}/tofu.tfstate"
#   }
# }

// Generates provider.tf in each unit at plan/apply time.
// `resource_provider_registrations = "none"` prevents the provider from auto-registering resource providers, which needs elevated permissions.
// Docs: https://search.opentofu.org/provider/terraform-providers/azurerm/latest
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
}

provider "azuread" {}
EOF
}
ROOT_HCL_EOF

log_info "root.hcl is in place. The remote_state block is commented out and will be enabled after bootstrap."
exit 0
)

# --- Install the pinned tool dependencies ------------------------
phase_install_deps() (
# The versions come from the generate step, not straight from the form: that is where the form
# override, the newest resolved release and the built-in pin are reconciled. Reading its result back
# keeps what gets installed here identical to what was rendered into the repository.

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

cd "$REPO_FILES"

if [ ! -f .mise.toml ] && [ ! -f mise.toml ] && [ ! -f .config/mise/config.toml ]; then
  # No mise config in the repo (an existing repo not scaffolded from this catalog). Create one matching
  # what the catalog's infrastructure-live template generates for Azure: Terragrunt and OpenTofu from
  # your inputs, plus the Azure CLI and Python pinned to the catalog defaults (some az extensions need
  # Python).
  log_warn "No mise config found in the repository; pinning Terragrunt, OpenTofu, azure-cli, and python."
  # A repository can already record which binary Pipelines will run. Honour it over the form,
  # or CI installs one binary and runs the other.
  IAC_PIN="opentofu@${OPENTOFU_VERSION}"
  if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
    recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
    case "$recorded" in
      terraform) IAC_PIN="terraform@${TERRAFORM_VERSION}"; log_warn "This repository records tf_binary = \"terraform\"; pinning Terraform." ;;
      opentofu)  IAC_PIN="opentofu@${OPENTOFU_VERSION}" ;;
    esac
  fi
  mise use "terragrunt@${TERRAGRUNT_VERSION}" "$IAC_PIN" "azure-cli@2.84.0" "python@3.14.3"
fi

# Trust before installing, not after. By this point a config always exists — the repository's own,
# or the one written just above — and `mise install` is the first thing to read it. A config that is
# more than plain [tools] pins (env, templated tool options) is skipped or errors while untrusted,
# so trusting afterwards would sit downstream of the very failure it prevents.
log_info "Trusting the repository's mise config..."
mise trust --all || log_warn "Could not trust the mise config; mise may prompt the first time you run it here."

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
)

# --- Add the Pipelines CI workflows ------------------------------
phase_add_ci_workflows() (
if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

if [ "$RB_out_read_details_repo_mode" = "scaffold" ]; then
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
)

# --- Write the repository README ---------------------------------
phase_write_readme() (
# A README that is still the stub GitHub creates with a new repository — a heading, maybe a one-line
# description, nothing else — carries no information worth keeping, and leaving it in place means the
# repository is left undocumented. Anything with real structure (sections, code, lists, links, tables)
# is somebody's work and is never touched.
readme_is_stub() {
  local f=$1 body
  # Any structural markdown means it is a real README.
  if grep -qE '^(##|```|[-*+] |[0-9]+\. |\||>)' "$f" || grep -q 'http' "$f"; then
    return 1
  fi
  body=$(grep -vE '^[[:space:]]*$' "$f" | wc -l | tr -d ' ')
  # A heading plus at most a couple of lines of blurb.
  [ "$body" -le 3 ] || return 1
  head -1 "$f" | grep -qE '^#[[:space:]]' || return 1
  return 0
}


if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  exit 1
fi

cd "$REPO_FILES"

TARGET="README.md"
if [ -f README.md ]; then
  if readme_is_stub README.md; then
    log_warn "README.md is still the stub created with the repository; replacing it."
    log_warn "Replacing this content:"
    while IFS= read -r line; do log_warn "    ${line}"; done < README.md
    TITLE=$(head -1 README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
  else
    # A README with real content belongs to whoever wrote it. Write the generated one alongside it
    # instead, so nothing is lost and the choice of whether to adopt it stays with the reader.
    TARGET="README.template.md"
    TITLE=$(grep -m1 -E '^#[[:space:]]' README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    log_info "README.md already exists and has real content; leaving it untouched."
    log_info "Writing the generated documentation to README.template.md instead."
  fi
fi
[ -n "${TITLE:-}" ] || TITLE="infrastructure-live"

TOOL="opentofu"
if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
  recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
  [ -n "$recorded" ] && TOOL="$recorded"
fi

cat > "$TARGET" <<'READMEEOF'
# __RB_TITLE__

Infrastructure [repo](https://docs.terragrunt.com/guides/ci-with-terragrunt/terragrunt-scale/#repository-structure) for this organization, managed with [Terragrunt Scale](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview) and deployed by [Gruntwork Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview).

```
████████╗███████╗██████╗ ██████╗  █████╗  ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║   ██║████╗  ██║╚══██╔══╝
   ██║   █████╗  ██████╔╝██████╔╝███████║██║  ███╗██████╔╝██║   ██║██╔██╗ ██║   ██║
   ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║
   ██║   ███████╗██║  ██║██║  ██║██║  ██║╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║   ██║
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝
                                                                           ▄▄▄
                    ███████╗ ██████╗ █████╗ ██╗     ███████╗             ▄▀░░░▀▄
                    ██╔════╝██╔════╝██╔══██╗██║     ██╔════╝           ▄▀░░░░░░░▀▄
                    ███████╗██║     ███████║██║     █████╗           ▄▀░░░░░░░░░░░▀▄
                    ╚════██║██║     ██╔══██║██║     ██╔══╝           █▀▄░░░░░░░░░▄▀█
                    ███████║╚██████╗██║  ██║███████╗███████╗         █▓▓▀▄░░░░░▄▀▒▒█
                    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝         █▓▓▓▓▀▄▄▄▀▒▒▒▒█
By Gruntwork                                                          ▀▄▓▓▓▓█▒▒▒▒▄▀
                                                                        ▀▄▓▓█▒▒▄▀
                                                                          ▀▄█▄▀
```

Changes are made by pull request. Opening one runs `terragrunt plan`; merging to `__RB_BRANCH__`
runs `terragrunt apply`. Nothing is applied from a laptop in normal operation.

## Repository layout

```
.
├── root.hcl
├── .mise.toml
├── .gitignore
├── pipelines-bootstrap-example.svg
├── .gruntwork/
│   ├── repository.hcl
│   └── environment-<subscription>.hcl
├── .github/
│   └── workflows/
│       ├── pipelines.yml
│       ├── pipelines-unlock.yml
│       └── pipelines-drift-detection.yml
└── <subscription>/
    ├── README.md
    ├── pipelines-bootstrap.svg
    ├── sub.hcl
    └── bootstrap/
        └── terragrunt.stack.hcl
```

| Path | What it is |
| --- | --- |
| `root.hcl` | Root Terragrunt config: azurerm remote state, the azurerm/azuread providers, shared inputs |
| `.mise.toml` | Pinned tool versions (Terragrunt, __RB_TOOL__, Azure CLI, Python) |
| `.gruntwork/repository.hcl` | Repository-wide Pipelines settings: deploy branch, `tf_binary` |
| `.gruntwork/environment-<subscription>.hcl` | Which subscription this environment deploys into, and the client IDs Pipelines authenticates as |
| `.github/workflows/pipelines.yml` | Plan on pull requests, apply on merge to `__RB_BRANCH__` |
| `.github/workflows/pipelines-unlock.yml` | Manually release a stuck state lock |
| `.github/workflows/pipelines-drift-detection.yml` | Scheduled drift detection, if enabled |
| `pipelines-bootstrap-example.svg` | The illustration in the bootstrap section below |
| `<subscription>/README.md` | What this subscription's bootstrap provisioned, with its identifiers |
| `<subscription>/pipelines-bootstrap.svg` | The same, drawn with this subscription's real values |
| `<subscription>/sub.hcl` | Subscription-level values: subscription and tenant ids, state storage |
| `<subscription>/bootstrap/` | The bootstrap stack (see below) |

Each additional subscription is another top-level directory with the same shape, plus its own
`.gruntwork/environment-<subscription>.hcl`.

## How the pieces fit

**`root.hcl`** is included by every unit. It configures the azurerm backend — one state blob per unit,
keyed by its path — and generates the `azurerm` and `azuread` providers. Change it only when something
applies to the whole repository.

Note that the `remote_state` block starts commented out. The first bootstrap apply has to run against
local state, because the Storage Account holding the state does not exist yet. Once it does, the block
is uncommented and the state migrated into it — the runbook does both.

**`.gruntwork/repository.hcl`** is Pipelines' repository-wide configuration: the deploy branch, and
`tf_binary` (this repository uses **__RB_TOOL__**). `.gruntwork/environment-<subscription>.hcl` maps an
environment to its subscription and records the plan/apply client IDs.

**The bootstrap stack** (`<subscription>/bootstrap/terragrunt.stack.hcl`) provisions what Pipelines needs
before it can deploy anything into the subscription:

- an Entra ID application and service principal for `terragrunt plan` (read-only, used on pull requests),
- an Entra ID application and service principal for `terragrunt apply` (used on merges to the deploy branch),
- federated identity credentials binding each application to this repository's GitHub OIDC tokens,
- the resource group, Storage Account `__RB_STORAGE__` and container that hold OpenTofu state.

![Example bootstrap topology](pipelines-bootstrap-example.svg)

*Example labels. Every subscription bootstrapped into this repository also gets its own copy of this
diagram, drawn with that subscription's real identifiers, at `<subscription>/pipelines-bootstrap.svg`.*

Federated credentials mean no client secrets: GitHub's OIDC token is exchanged for an Entra ID token
at run time.

It is applied once, when the subscription is onboarded. After that it is ordinary configuration:
changes to it go through the same plan/apply flow as anything else.

**The workflows** call Gruntwork's reusable workflow rather than containing the logic themselves, so
upgrading Pipelines is a version bump in `.github/workflows/pipelines.yml`.

**`.mise.toml`** pins the tool versions. CI installs exactly these, so a local run matches CI. Run
`mise trust` then `mise install` once after cloning.

## Working in this repository

```bash
mise trust                      # allow mise to load this repo's config
mise install                    # install the pinned tool versions
az login
cd <subscription>/bootstrap
terragrunt run --all plan       # see what would change
```

Open a pull request with your change and let Pipelines plan it. Read the plan in the PR comment
before merging — merging is what applies it.

## Adding another subscription

Re-run the Gruntwork Runbook that created this repository and give it a new subscription name. It adds
a new top-level directory and a new `.gruntwork/environment-<subscription>.hcl`, and leaves everything here
untouched.

## Reference

- [Pipelines overview](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview)
- [Configuration as code reference](https://docs.gruntwork.io/2.0/reference/pipelines/configurations-as-code/api)
- [Terragrunt documentation](https://terragrunt.gruntwork.io)
READMEEOF

sed -i.bak \
  -e "s|__RB_TITLE__|${TITLE}|g" \
  -e "s|__RB_BRANCH__|${RB_DeployBranch}|g" \
  -e "s|__RB_PREFIX__|${RB_OIDCResourcePrefix}|g" \
  -e "s|__RB_STORAGE__|${RB_StateStorageAccountName}|g" \
  -e "s|__RB_TOOL__|${TOOL}|g" "$TARGET"
rm -f "$TARGET.bak"


# The illustration for the README's bootstrap section. Unlike the per-subscription diagrams this one is
# fixed: it shows the shape of the thing with placeholder labels, so it is written once and never
# needs regenerating. It is committed with the README that references it.
#
# ASCII only: the app's SVG preview does btoa(svgText), which throws above U+00FF and then renders
# nothing. Angle brackets in the placeholder labels are written as entities.
write_example_diagram() {
  cat > pipelines-bootstrap-example.svg <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="590" viewBox="0 0 760 590" font-family="Helvetica, Arial, sans-serif">
  <rect width="760" height="590" fill="#ffffff"/>
  <text x="380" y="34" text-anchor="middle" font-size="17" font-weight="bold" fill="#1a1a1a">Gruntwork Pipelines bootstrap</text>
  <text x="380" y="54" text-anchor="middle" font-size="12" fill="#666666">what the stack provisions in each Azure subscription</text>

  <rect x="130" y="80" width="500" height="62" rx="6" fill="#f4f6f8" stroke="#5b6b7c" stroke-width="1.5"/>
  <text x="380" y="103" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GitHub Actions</text>
  <text x="380" y="121" text-anchor="middle" font-size="11" fill="#444444">&lt;org&gt;/&lt;repo&gt;</text>
  <text x="380" y="136" text-anchor="middle" font-size="11" fill="#444444">deploy branch: &lt;deploy-branch&gt;</text>

  <line x1="380" y1="142" x2="380" y2="182" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="392" y="167" font-size="10" fill="#666666">OIDC token</text>

  <rect x="150" y="182" width="460" height="66" rx="6" fill="#fdf3e3" stroke="#c98a1b" stroke-width="1.5"/>
  <text x="380" y="205" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Entra ID federated credentials</text>
  <text x="380" y="223" text-anchor="middle" font-size="11" fill="#444444">tenant &lt;tenant-id&gt;</text>
  <text x="380" y="239" text-anchor="middle" font-size="10" fill="#666666">no client secrets</text>

  <line x1="300" y1="248" x2="190" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="460" y1="248" x2="570" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="20" y="304" width="350" height="102" rx="6" fill="#eef5ee" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan application</text>
  <text x="195" y="346" text-anchor="middle" font-size="10" fill="#444444">&lt;prefix&gt;-plan</text>
  <text x="195" y="363" text-anchor="middle" font-size="10" fill="#444444">role: &lt;prefix&gt;-plan-custom-role</text>
  <text x="195" y="381" text-anchor="middle" font-size="10" fill="#666666">signs in on pull requests</text>
  <text x="195" y="397" text-anchor="middle" font-size="10" fill="#666666">read only</text>

  <rect x="390" y="304" width="350" height="102" rx="6" fill="#fdeeee" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply application</text>
  <text x="565" y="346" text-anchor="middle" font-size="10" fill="#444444">&lt;prefix&gt;-apply</text>
  <text x="565" y="363" text-anchor="middle" font-size="10" fill="#444444">role: &lt;prefix&gt;-apply-custom-role</text>
  <text x="565" y="381" text-anchor="middle" font-size="10" fill="#666666">signs in on merges to the deploy branch</text>
  <text x="565" y="397" text-anchor="middle" font-size="10" fill="#666666">creates and changes infrastructure</text>

  <line x1="195" y1="406" x2="330" y2="470" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="565" y1="406" x2="430" y2="470" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="170" y="474" width="420" height="82" rx="6" fill="#eef2f8" stroke="#3f5f8d" stroke-width="1.5"/>
  <text x="380" y="497" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">State storage</text>
  <text x="380" y="515" text-anchor="middle" font-size="11" fill="#444444">&lt;storage-account&gt; / &lt;container&gt;</text>
  <text x="380" y="531" text-anchor="middle" font-size="10" fill="#666666">resource group: &lt;state-rg&gt;</text>
  <text x="380" y="547" text-anchor="middle" font-size="10" fill="#666666">one state file per unit</text>

  <text x="380" y="578" text-anchor="middle" font-size="10" fill="#999999">Example. Each subscription has its own diagram at &lt;subscription&gt;/pipelines-bootstrap.svg</text>

  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/>
    </marker>
  </defs>
</svg>
SVGEOF
  log_info "Wrote pipelines-bootstrap-example.svg (illustrates the README's bootstrap section)."
}

write_example_diagram

# With the environment name out of the document, bootstrapping another one into this repository
# renders exactly the same README. Dropping an identical README.template.md beside it keeps repeat
# runs from leaving a file that says nothing new. Compared before the banner is prepended.
if [ "$TARGET" = "README.template.md" ] && [ -f README.md ] && cmp -s "$TARGET" README.md; then
  rm -f "$TARGET"
  log_info "README.md is already this document; nothing to add."
  exit 0
fi

if [ "$TARGET" = "README.template.md" ]; then
  # Say what this file is, at the top, so nobody has to guess where it came from.
  tmp=$(mktemp)
  {
    printf '%s\n' "<!--"
    printf '%s\n' "  Generated by the Gruntwork Runbook that set up this repository."
    printf '%s\n' ""
    printf '%s\n' "  Your repository already had a README, so this was written alongside it rather than over it."
    printf '%s\n' "  Adopt it with:  mv README.template.md README.md"
    printf '%s\n' "  Or take the parts you want and delete the rest — nothing depends on this file."
    printf '%s\n' "-->"
    printf '%s\n' ""
    cat "$TARGET"
  } > "$tmp" && mv "$tmp" "$TARGET"
  log_info "Wrote README.template.md alongside your README.md. Review it, then rename it over README.md"
  log_info "if you want it, or delete it — nothing depends on it."
  exit 0
fi

log_info "Wrote README.md describing the repository layout, bootstrap stack, workflows and Pipelines config."
exit 0
)


# ---------------------------------------------------------------------------
# Run them in order
# ---------------------------------------------------------------------------

run_phase() {
  title=$1; fn=$2
  log_info ""
  log_info "=== ${title} ==="
  set +e
  "$fn"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    log_error "${title} failed (exit ${rc})."
    log_error "The phases after it did not run. Fix the problem and run this step again."
    exit "$rc"
  fi
}

run_phase "Render the Terragrunt Scale configuration" phase_generate
run_phase "Ensure root.hcl is present" phase_ensure_root_hcl
run_phase "Install the pinned tool dependencies" phase_install_deps
run_phase "Add the Pipelines CI workflows" phase_add_ci_workflows
run_phase "Write the repository README" phase_write_readme

log_info ""
log_info "Repository set up: configuration rendered, tools installed, CI workflows and README written."
exit 0
