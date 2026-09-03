#!/bin/bash
# Work out which existing AWS resources the bootstrap should adopt instead of create.
#
# Import targets are named by full ARN, not discovered from a prefix. IAM policies are
# content-addressed -- the module names them "<name>-<8 of sha256(document)>" -- so several
# generations of the same policy can sit in an account at once, and no prefix identifies which one
# is meant. Guessing fails late and in both directions: adopt nothing and the apply collides on a
# duplicate name, adopt the wrong one and the plan fails on a target that is not there.
#
# So this lists what is in the account, for the ARNs to be copied from, and then checks that
# whatever was named actually exists before anything is generated.
set -uo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
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

# "none" is the form's default for every optional ARN: a non-empty sentinel, because a blank
# optional input leaves the block waiting on an unmet dependency and it can never be run.
unset_if_none() {
  case "$1" in none|"") printf '' ;; *) printf '%s' "$1" ;; esac
}

RB_AddStsAudienceIfMissing=$(rb_unquote "{{ .inputs.AddStsAudienceIfMissing }}")
RB_ApplyIAMPolicyImportArn=$(unset_if_none "$(rb_unquote "{{ .inputs.ApplyIAMPolicyImportArn }}")")
RB_ApplyIAMRoleImportArn=$(unset_if_none "$(rb_unquote "{{ .inputs.ApplyIAMRoleImportArn }}")")
RB_ExistingOIDCProvider=$(rb_unquote "{{ .inputs.ExistingOIDCProvider }}")
RB_Issuer=$(unset_if_none "$(rb_unquote "{{ .inputs.Issuer }}")")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_PlanIAMPolicyImportArn=$(unset_if_none "$(rb_unquote "{{ .inputs.PlanIAMPolicyImportArn }}")")
RB_PlanIAMRoleImportArn=$(unset_if_none "$(rb_unquote "{{ .inputs.PlanIAMRoleImportArn }}")")
RB_out_clone_org_id=$(rb_unquote "{{ .outputs.clone.org_id }}")
RB_out_clone_repo_id=$(rb_unquote "{{ .outputs.clone.repo_id }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")
RB_out_read_details_aws_account_id=$(rb_unquote "{{ .outputs.read_details.aws_account_id }}")
RB_out_read_details_partition=$(rb_unquote "{{ .outputs.read_details.partition }}")

ACCOUNT="$RB_out_read_details_aws_account_id"
PARTITION="$RB_out_read_details_partition"
PREFIX="$RB_OIDCResourcePrefix"

# An OIDC provider has no name: it is addressed by its issuer host, and that decides which provider
# is looked for, imported and trusted.
if [ -z "$RB_Issuer" ]; then
  ISSUER_HOST="token.actions.githubusercontent.com"
else
  ISSUER_HOST=${RB_Issuer#https://}
  ISSUER_HOST=${ISSUER_HOST#http://}
  ISSUER_HOST=${ISSUER_HOST%/}
  log_info "Using a non-default OIDC issuer: ${RB_Issuer}"
fi
OIDC_PROVIDER_ARN="arn:${PARTITION}:iam::${ACCOUNT}:oidc-provider/${ISSUER_HOST}"

# ---------------------------------------------------------------------------
# What is already in this account
# ---------------------------------------------------------------------------

# Roles that trust this repository through the provider, so their ARNs can be copied into the form.
# ListRoles returns every trust policy, so this is one paginated call rather than a get-role each.
list_trusting_roles() {
  local json rc=0
  json=$(aws iam list-roles --output json 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    log_warn "  cannot list roles (iam:ListRoles denied?), so none can be listed here."
    return 0
  fi
  printf '%s' "$json" | jq -r --arg prov "$OIDC_PROVIDER_ARN" \
    --arg a "repo:${RB_out_clone_repo_owner}@${RB_out_clone_org_id}/${RB_out_clone_repo_name}@${RB_out_clone_repo_id}:" \
    --arg b "repo:${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}:" '
    .Roles[]? as $r
    | ($r.AssumeRolePolicyDocument.Statement // [])[]
    | select((.Action == "sts:AssumeRoleWithWebIdentity") or (.Action[]? == "sts:AssumeRoleWithWebIdentity"))
    | select(.Principal.Federated == $prov)
    | (.Condition // {}) | to_entries[] as $op
    | $op.value | to_entries[]
    | select(.key | endswith(":sub"))
    | (if (.value | type) == "array" then .value[] else .value end) as $sub
    | [$r.Arn, (if ($sub | startswith($a)) or ($sub | startswith($b)) then "this repository" else "another repository" end), $op.key, $sub]
    | @tsv' 2>/dev/null | sort -u
}

# The policies attached to those roles are the ones worth adopting; an account can hold several
# generations of the same policy, so they are listed with the role they hang off.
list_role_policies() {
  local role_arn role_name json
  while IFS=$'\t' read -r role_arn _ _ _; do
    [ -n "$role_arn" ] || continue
    role_name=${role_arn##*/}
    json=$(aws iam list-attached-role-policies --role-name "$role_name" --output json 2>/dev/null) || continue
    printf '%s' "$json" | jq -r --arg r "$role_name" '.AttachedPolicies[]? | [$r, .PolicyArn] | @tsv' 2>/dev/null
  done < "$ROLES_FILE"
}

ROLES_FILE=$(mktemp)
POLICIES_FILE=$(mktemp)
trap 'rm -f "$ROLES_FILE" "$POLICIES_FILE"' EXIT

log_info ""
log_info "Roles trusting ${OIDC_PROVIDER_ARN}:"
list_trusting_roles > "$ROLES_FILE"
if [ -s "$ROLES_FILE" ]; then
  while IFS=$'\t' read -r arn whose op sub; do
    log_info "  ${arn}"
    log_info "      trusts ${whose}  (${op} ${sub})"
  done < "$ROLES_FILE"
else
  log_info "  none."
fi

log_info ""
log_info "Policies attached to those roles:"
list_role_policies > "$POLICIES_FILE"
if [ -s "$POLICIES_FILE" ]; then
  while IFS=$'\t' read -r role arn; do log_info "  ${arn}   (attached to ${role})"; done < "$POLICIES_FILE"
else
  log_info "  none."
fi
log_info ""
log_info "To adopt any of these, copy its ARN into the matching field in the form above and run this"
log_info "step again. Anything left as none is created fresh."

# ---------------------------------------------------------------------------
# Check what was asked for
# ---------------------------------------------------------------------------

fail=0

check_role_arn() {
  local label=$1 arn=$2 name doc
  [ -n "$arn" ] || return 0
  name=${arn##*/}
  case "$arn" in
    arn:*:iam::*:role/*) : ;;
    *) log_error "${label}: [${arn}] is not an IAM role ARN."; fail=1; return 0 ;;
  esac
  if ! aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    log_error "${label}: no role named ${name} in this account. Copy an ARN from the list above."
    fail=1; return 0
  fi
  # Adopting a role rewrites its trust policy, so taking one that belongs elsewhere breaks it.
  doc=$(aws iam get-role --role-name "$name" --output json 2>/dev/null | jq -c '.Role.AssumeRolePolicyDocument' 2>/dev/null)
  if ! printf '%s' "$doc" | grep -q "${RB_out_clone_repo_name}"; then
    log_warn "${label}: ${name} does not appear to trust this repository. Adopting it rewrites its"
    log_warn "  trust policy, which stops whatever uses it today from working."
  fi
  log_info "${label}: adopting ${name}"
}

check_policy_arn() {
  local label=$1 arn=$2
  [ -n "$arn" ] || return 0
  case "$arn" in
    arn:*:iam::*:policy/*) : ;;
    *) log_error "${label}: [${arn}] is not an IAM policy ARN."; fail=1; return 0 ;;
  esac
  if ! aws iam get-policy --policy-arn "$arn" >/dev/null 2>&1; then
    log_error "${label}: no policy at ${arn}. Copy an ARN from the list above."
    fail=1; return 0
  fi
  log_info "${label}: adopting ${arn}"
}

log_info ""
check_role_arn   "Plan role"    "$RB_PlanIAMRoleImportArn"
check_role_arn   "Apply role"   "$RB_ApplyIAMRoleImportArn"
check_policy_arn "Plan policy"  "$RB_PlanIAMPolicyImportArn"
check_policy_arn "Apply policy" "$RB_ApplyIAMPolicyImportArn"
[ "$fail" -eq 0 ] || exit 1

# The attachment is fully determined by the two ARNs, so it is not asked for -- but it is only
# adopted when it actually exists, otherwise the import would have nothing to point at.
attachment_id() {
  local role_arn=$1 policy_arn=$2 role_name
  [ -n "$role_arn" ] && [ -n "$policy_arn" ] || return 0
  role_name=${role_arn##*/}
  if aws iam list-attached-role-policies --role-name "$role_name" --output json 2>/dev/null \
     | jq -e --arg a "$policy_arn" 'any(.AttachedPolicies[]?; .PolicyArn == $a)' >/dev/null 2>&1; then
    printf '%s/%s' "$role_name" "$policy_arn"
  fi
}
PLAN_ATTACH_ID=$(attachment_id "$RB_PlanIAMRoleImportArn" "$RB_PlanIAMPolicyImportArn")
APPLY_ATTACH_ID=$(attachment_id "$RB_ApplyIAMRoleImportArn" "$RB_ApplyIAMPolicyImportArn")
[ -n "$PLAN_ATTACH_ID" ] && log_info "Plan attachment: adopting ${PLAN_ATTACH_ID}"
[ -n "$APPLY_ATTACH_ID" ] && log_info "Apply attachment: adopting ${APPLY_ATTACH_ID}"

# ---------------------------------------------------------------------------
# OIDC provider
# ---------------------------------------------------------------------------

OIDC_JSON=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" --output json 2>/dev/null || printf '')
OIDC_IMPORT=false
EXCLUDE_OIDC=false
ADDITIONAL_AUDIENCES="[]"
OIDC_TAGS="{}"

log_info ""
if [ -z "$OIDC_JSON" ]; then
  log_info "No OIDC provider at ${ISSUER_HOST}; the bootstrap will create one."
else
  # The desired state replaces the audience list wholesale, so anything already trusted has to be
  # carried across or the apply would drop it.
  ADDITIONAL_AUDIENCES=$(printf '%s' "$OIDC_JSON" | jq -c '[.ClientIDList[]? | select(. != "sts.amazonaws.com")]' 2>/dev/null || printf '[]')
  OIDC_TAGS=$(printf '%s' "$OIDC_JSON" | jq -c '(.Tags // []) | map({(.Key): .Value}) | add // {}' 2>/dev/null || printf '{}')
  HAS_STS=$(printf '%s' "$OIDC_JSON" | jq -r 'if (.ClientIDList // []) | index("sts.amazonaws.com") then "true" else "false" end' 2>/dev/null || printf 'false')
  log_info "OIDC provider ${OIDC_PROVIDER_ARN} exists (trusts sts.amazonaws.com: ${HAS_STS})."

  case "$RB_ExistingOIDCProvider" in
    import)
      OIDC_IMPORT=true
      log_info "Importing it; the apply adds the sts.amazonaws.com audience if it is missing."
      ;;
    leave-alone)
      EXCLUDE_OIDC=true
      log_warn "Leaving it alone: the stack omits the OIDC provider entirely."
      if [ "$HAS_STS" != "true" ]; then
        if [ "$RB_AddStsAudienceIfMissing" = "true" ]; then
          if aws iam add-client-id-to-open-id-connect-provider \
               --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" --client-id "sts.amazonaws.com"; then
            log_info "Added the sts.amazonaws.com audience."
          else
            log_error "Could not add the audience. Add it by hand, then run this step again."
            exit 1
          fi
        else
          log_error "This provider does not trust sts.amazonaws.com and nothing here will manage it."
          log_error "Set ExistingOIDCProvider to import, or AddStsAudienceIfMissing to true, or run:"
          log_error "  aws iam add-client-id-to-open-id-connect-provider \\"
          log_error "    --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN} --client-id sts.amazonaws.com"
          exit 1
        fi
      fi
      ;;
    *) log_error "Unknown ExistingOIDCProvider value [${RB_ExistingOIDCProvider}]."; exit 1 ;;
  esac
fi

{
  echo "oidc_import_existing=${OIDC_IMPORT}"
  echo "exclude_oidc_provider=${EXCLUDE_OIDC}"
  echo "additional_audiences=${ADDITIONAL_AUDIENCES}"
  echo "oidc_provider_tags=${OIDC_TAGS}"
  echo "plan_role_import=$([ -n "$RB_PlanIAMRoleImportArn" ] && echo true || echo false)"
  echo "apply_role_import=$([ -n "$RB_ApplyIAMRoleImportArn" ] && echo true || echo false)"
  echo "plan_role_name=${RB_PlanIAMRoleImportArn##*/}"
  echo "apply_role_name=${RB_ApplyIAMRoleImportArn##*/}"
  echo "plan_policy_arn=${RB_PlanIAMPolicyImportArn}"
  echo "apply_policy_arn=${RB_ApplyIAMPolicyImportArn}"
  echo "plan_attachment_id=${PLAN_ATTACH_ID}"
  echo "apply_attachment_id=${APPLY_ATTACH_ID}"
} >> "$RUNBOOK_OUTPUT"

log_info ""
log_info "Import plan settled. Anything not named above is created fresh."
exit 0
