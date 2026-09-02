#!/bin/bash
# Read everything the rest of the runbook is shaped by, in one pass, and publish it:
#
#   azure_tenant_id       - from your active `az` session
#   azure_subscription_id - the subscription that session is pointed at
#   deploy_branch         - the branch the clone is on. Pipelines applies on merges here, and the
#                           setup pull request targets it. Read from the repository, not typed.
#   repo_mode             - "account" when a root `root.hcl` is present (an existing Terragrunt
#                           Scale repository: only the new subscription is added), "scaffold" when
#                           it is absent.
#
# Also exports ARM_TENANT_ID / ARM_SUBSCRIPTION_ID for the Terragrunt steps that follow — those env
# vars are how the azurerm/azuread providers pick the target subscription, and they persist to later
# blocks in this session.
#
# Nothing else is changed here — this only looks.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  log_error "If the repository has no commits yet, use the clone block's **Create default branch**"
  log_error "button — the clone holds back its outputs until the branch exists."
  exit 1
fi

# --- Azure identity ----------------------------------------------------------
# An az session expires like any other; say so plainly rather than failing obscurely further in.
if ! account=$(az account show --query '[tenantId,id]' -o tsv 2>&1); then
  log_error "Could not read your Azure session: ${account}"
  log_error "Re-run the 'Sign in with az login' step above and select the target subscription,"
  log_error "then run this check again."
  exit 1
fi
TENANT_ID=$(printf '%s' "$account" | awk '{print $1}')
SUBSCRIPTION_ID=$(printf '%s' "$account" | awk '{print $2}')

if [ -z "$TENANT_ID" ] || [ -z "$SUBSCRIPTION_ID" ]; then
  log_error "Could not read tenant/subscription from az. Run the 'Sign in with az login' step and select a subscription first."
  exit 1
fi

# Persist for later Terragrunt blocks in this session.
export ARM_TENANT_ID="$TENANT_ID"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

log_info "Azure tenant:  ${TENANT_ID}"
log_info "Subscription:  ${SUBSCRIPTION_ID}"

# --- the repository ----------------------------------------------------------
cd "$REPO_FILES"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  log_error "Could not determine the current branch of ${REPO_FILES}."
  log_error "A detached HEAD or a repository with no commits has no branch to deploy from."
  log_error "Check out the branch Pipelines should deploy from, then run this check again."
  exit 1
fi

if [ -f root.hcl ]; then MODE="account"; else MODE="scaffold"; fi

log_info "Deploy branch: ${BRANCH}  (read from the repository, not typed)"
log_info "Repository:    ${MODE}"
if [ "$MODE" = "account" ]; then
  log_info "  Found root.hcl — an existing Terragrunt Scale repository. This run adds the new"
  log_info "  subscription to it and leaves the existing configuration alone."
else
  log_info "  No root.hcl — not set up for Terragrunt Scale yet. This run renders the full"
  log_info "  repository layout (root.hcl, .mise.toml, CI workflows) into it."
fi

log_info "If you changed branches after selecting the repository above, select it again so the"
log_info "pull request targets ${BRANCH} too."

{
  echo "azure_tenant_id=${TENANT_ID}"
  echo "azure_subscription_id=${SUBSCRIPTION_ID}"
  echo "deploy_branch=${BRANCH}"
  echo "repo_mode=${MODE}"
} >> "$RUNBOOK_OUTPUT"
exit 0
