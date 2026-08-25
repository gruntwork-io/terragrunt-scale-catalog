#!/bin/bash
# Confirm the organization (or user) entered in the form exists and is reachable with this
# token, so a typo fails here instead of part-way through repository creation.
set -uo pipefail

OWNER="{{ .inputs.GitHubOrgName }}"

if [ -z "$OWNER" ]; then
  log_error "GitHubOrgName is empty. Fill in the repository form first."
  exit 1
fi

if gh api "orgs/${OWNER}" --jq '.login' >/dev/null 2>&1; then
  log_info "${OWNER} is a GitHub organization reachable with this token."
  exit 0
fi

if gh api "users/${OWNER}" --jq '.login' >/dev/null 2>&1; then
  me=$(gh api user --jq '.login' 2>/dev/null || echo "")
  if [ -n "$me" ] && [ "$me" != "$OWNER" ]; then
    log_warn "${OWNER} is a personal account, and you are authenticated as ${me}."
    log_warn "Repository creation will fail unless ${OWNER} is your own account."
    exit 2
  fi
  log_info "${OWNER} is your personal GitHub account."
  exit 0
fi

log_error "No GitHub organization or user named '${OWNER}' is visible with this token."
log_error "Check the spelling, or confirm the token can see that organization (it may need the 'read:org' scope)."
exit 1
