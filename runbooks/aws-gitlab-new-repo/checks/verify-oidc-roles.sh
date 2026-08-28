#!/bin/bash
# Confirm the plan/apply IAM roles the bootstrap stack manages exist in the account.
#
# A bare "not found" is ambiguous — the role may be missing, the credentials may not allow reading
# it, or the roles may simply be named with a different prefix than the one in the form (common when
# an account was bootstrapped previously). Each case is reported distinctly.
set -uo pipefail

rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
PREFIX="${RB_OIDCResourcePrefix}"

if [ -z "$PREFIX" ]; then
  log_error "OIDCResourcePrefix is empty. Fill it in above and re-run this check."
  exit 1
fi

# Distinguish "cannot reach AWS" from "role is missing".
if ! ident=$(aws sts get-caller-identity --output text --query 'Account' 2>&1); then
  log_error "Could not reach AWS with the current credentials: ${ident}"
  log_error "Re-authenticate in the AWS step above, then run this check again."
  exit 1
fi
log_info "Checking account ${ident} for the ${PREFIX}-plan and ${PREFIX}-apply roles."

rc=0
missing=""
for role in "${PREFIX}-plan" "${PREFIX}-apply"; do
  if err=$(aws iam get-role --role-name "$role" 2>&1 >/dev/null); then
    log_info "IAM role ${role} exists."
  elif printf '%s' "$err" | grep -q 'AccessDenied'; then
    log_warn "Not permitted to read IAM role ${role} (iam:GetRole denied)."
    log_warn "The role may well exist; this check cannot confirm it with these credentials."
    [ "$rc" -eq 0 ] && rc=2
  else
    log_error "IAM role ${role} not found in account ${ident}."
    missing="${missing} ${role}"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  log_info "Both OIDC IAM roles are present."
  exit 0
fi

if [ -n "$missing" ]; then
  # Show what IS there, so a prefix mismatch is obvious rather than a guess.
  log_error "Roles in this account whose name suggests Pipelines OIDC use:"
  found=$(aws iam list-roles --query 'Roles[?contains(RoleName, `plan`) || contains(RoleName, `apply`) || contains(RoleName, `pipelines`)].RoleName' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d')
  if [ -n "$found" ]; then
    printf '%s\n' "$found" | while IFS= read -r r; do log_error "    ${r}"; done
    log_error "If the roles above are yours, set OIDCResourcePrefix to their common prefix and re-run."
  else
    log_error "    (none found, or iam:ListRoles is not permitted)"
    log_error "If the bootstrap apply step reported success, check you are authenticated to the same"
    log_error "account it applied to. Otherwise re-run the apply step."
  fi
fi
exit "$rc"
