#!/bin/bash
# Read everything the rest of the runbook is shaped by, in one pass, and publish it:
#
#   aws_account_id - the account your confirmed credentials belong to
#   partition      - aws / aws-us-gov / aws-cn, from the identity's ARN
#   deploy_branch  - the branch the clone is on. Pipelines applies on merges here, and the setup
#                    pull request targets it. Read from the repository so the two cannot disagree.
#   repo_mode      - "account" when a root `root.hcl` is present (an existing Terragrunt Scale
#                    repository: only the new account is added), "scaffold" when it is absent (the
#                    full repository layout is rendered into it).
#
# Nothing is changed here — this only looks. Everything below depends on all four, so the runbook
# cannot continue until this passes.
set -uo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  log_error "If the repository has no commits yet, use the clone block's **Create default branch**"
  log_error "button — the clone holds back its outputs until the branch exists."
  exit 1
fi

# --- AWS identity ------------------------------------------------------------
# Temporary credentials routinely expire part-way through this runbook. Check reachability first so
# an expired session says so plainly, rather than surfacing as a confusing failure further in.
if ! identity=$(aws sts get-caller-identity --output text --query '[Arn,Account]' 2>&1); then
  log_error "Could not reach AWS with the current credentials: ${identity}"
  log_error "Re-run the AWS authentication step above to refresh them, then run this check again."
  exit 1
fi
ARN=$(printf '%s' "$identity" | awk '{print $1}')
ACCOUNT_ID=$(printf '%s' "$identity" | awk '{print $2}')

case "$ARN" in
  arn:aws-us-gov:*) PARTITION="aws-us-gov" ;;
  arn:aws-cn:*)     PARTITION="aws-cn" ;;
  *)                PARTITION="aws" ;;
esac

log_info "AWS account:   ${ACCOUNT_ID}  (partition ${PARTITION})"

# --- the repository ----------------------------------------------------------
cd "$REPO_FILES"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  log_error "Could not determine the current branch of ${REPO_FILES}."
  log_error "A detached HEAD or a repository with no commits has no branch to deploy from."
  log_error "Check out the branch Pipelines should deploy from, then run this check again."
  exit 1
fi

if [ -f root.hcl ]; then
  MODE="account"
else
  MODE="scaffold"
fi

log_info "Deploy branch: ${BRANCH}  (read from the repository, not typed)"
log_info "Repository:    ${MODE}"
if [ "$MODE" = "account" ]; then
  log_info "  Found root.hcl — an existing Terragrunt Scale repository. This run adds the new"
  log_info "  account to it and leaves the existing configuration alone."
else
  log_info "  No root.hcl — not set up for Terragrunt Scale yet. This run renders the full"
  log_info "  repository layout (root.hcl, .mise.toml, CI workflows) into it."
fi

# The clone block records the branch when you select or clone, and the pull request targets THAT
# branch. This reads git live, so switching branches in a local checkout afterwards changes what is
# published here without changing what the request will target.
log_info "If you changed branches after selecting the repository above, select it again so the"
log_info "pull request targets ${BRANCH} too."

# --- what is already in the account -------------------------------------------
# Reported here, before the form, so the import questions below can be answered against what is
# actually in the account rather than guessed. The authoritative pass runs after the form, once the
# OIDC resource prefix is known; this looks at the default prefix only.
# This runs before the form, so a custom Issuer is not known yet: report against GitHub's default
# and let the reconcile step, which does know it, be authoritative.
OIDC_ARN="arn:${PARTITION}:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
OIDC_JSON=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" --output json 2>/dev/null || printf '')

log_info ""
if [ -n "$OIDC_JSON" ]; then
  AUDIENCES=$(printf '%s' "$OIDC_JSON" | jq -r '.ClientIDList | join(", ")' 2>/dev/null)
  log_warn "A GitHub OIDC provider already exists in this account."
  log_warn "  audiences: ${AUDIENCES:-<none>}"
  case ",${AUDIENCES}," in
    *,sts.amazonaws.com,*) log_info "  It already trusts sts.amazonaws.com." ;;
    *) log_warn "  It does NOT list sts.amazonaws.com; Pipelines needs that audience." ;;
  esac
  log_info "  Answer ExistingOIDCProvider in the form below to say whether it should be imported."
else
  log_info "No OIDC provider for GitHub's default issuer in this account yet."
  log_info "  The bootstrap will create one. If you use GitHub Enterprise Server or an enterprise"
  log_info "  with unique token URLs, set Issuer in the form below and this is re-checked there."
fi

for role in pipelines-plan pipelines-apply; do
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    log_warn "IAM role ${role} already exists."
  fi
done
log_info "The bootstrap creates its own roles, so if these names are taken the step after the form"
log_info "stops and asks you for a different OIDCResourcePrefix."

{
  echo "aws_account_id=${ACCOUNT_ID}"
  echo "partition=${PARTITION}"
  echo "deploy_branch=${BRANCH}"
  echo "repo_mode=${MODE}"
} >> "$RUNBOOK_OUTPUT"
exit 0
