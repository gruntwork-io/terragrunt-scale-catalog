#!/bin/bash
# List the GitHub organizations this token can see so the form below can be filled with an
# exact org login rather than a guess. Informational: a warning here does not block anything.
set -uo pipefail

if ! orgs=$(gh api user/orgs --paginate --jq '.[].login' 2>/dev/null); then
  log_warn "Could not list organizations. The token is likely missing the 'read:org' scope."
  log_warn "You can still type the organization (or your own username) into the form below."
  exit 2
fi

me=$(gh api user --jq '.login' 2>/dev/null || echo "")

if [ -z "$orgs" ]; then
  log_warn "No organizations are visible to this token (it may be missing the 'read:org' scope)."
  [ -n "$me" ] && log_info "For a repository under your personal account, use: ${me}"
  exit 2
fi

log_info "Organizations available to you:"
while IFS= read -r org; do
  [ -n "$org" ] && log_info "  ${org}"
done <<< "$orgs"
[ -n "$me" ] && log_info "  ${me} (your personal account)"
log_info "Copy one of these into GitHubOrgName below."
exit 0
