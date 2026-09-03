#!/bin/bash
# Decide which existing AWS resources the bootstrap should adopt instead of create.
#
# The bootstrap stack fails on "already exists" if something it wants to create is already in the
# account. The catalog templates handle that with import blocks, one per resource, driven by the
# *ImportExisting variables. This works out which of those to set, using the OIDC resource prefix
# from the form, and publishes them for the generate step.
#
# Each of the six role resources is checked independently -- role, policy, attachment -- so a
# half-built setup adopts only the pieces that are actually there.
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

RB_AddStsAudienceIfMissing=$(rb_unquote "{{ .inputs.AddStsAudienceIfMissing }}")
RB_ExistingOIDCProvider=$(rb_unquote "{{ .inputs.ExistingOIDCProvider }}")
RB_ExistingPipelinesRoles=$(rb_unquote "{{ .inputs.ExistingPipelinesRoles }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_out_read_details_aws_account_id=$(rb_unquote "{{ .outputs.read_details.aws_account_id }}")
RB_out_read_details_partition=$(rb_unquote "{{ .outputs.read_details.partition }}")

ACCOUNT="$RB_out_read_details_aws_account_id"
PARTITION="$RB_out_read_details_partition"
PREFIX="$RB_OIDCResourcePrefix"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# "true" / "false" on stdout; a real AWS error is fatal rather than reported as absent, because
# treating a permissions failure as "does not exist" would make the apply try to create a duplicate.
aws_exists() {
  local what=$1; shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then printf 'true'; return 0; fi
  case $out in
    *NoSuchEntity*) printf 'false'; return 0 ;;
  esac
  log_error "Could not check ${what}: ${out}"
  return 1
}

policy_attached() {
  local role=$1 policy_arn=$2 out
  out=$(aws iam list-attached-role-policies --role-name "$role" --output json 2>/dev/null) || { printf 'false'; return 0; }
  if printf '%s' "$out" | jq -e --arg a "$policy_arn" 'any(.AttachedPolicies[]?; .PolicyArn == $a)' >/dev/null 2>&1; then
    printf 'true'
  else
    printf 'false'
  fi
}

# ---------------------------------------------------------------------------
# OIDC provider
# ---------------------------------------------------------------------------

OIDC_ARN="arn:${PARTITION}:iam::${ACCOUNT}:oidc-provider/token.actions.githubusercontent.com"
OIDC_JSON=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" --output json 2>/dev/null || printf '')

OIDC_IMPORT=false
EXCLUDE_OIDC=false
# Everything the provider already trusts, minus the audience the bootstrap adds itself. The desired
# state replaces the audience list wholesale, so anything not carried across here would be removed.
ADDITIONAL_AUDIENCES="[]"
OIDC_TAGS="{}"

if [ -z "$OIDC_JSON" ]; then
  log_info "No GitHub OIDC provider in this account; the bootstrap will create one."
else
  ADDITIONAL_AUDIENCES=$(printf '%s' "$OIDC_JSON" | jq -c '[.ClientIDList[]? | select(. != "sts.amazonaws.com")]' 2>/dev/null || printf '[]')
  OIDC_TAGS=$(printf '%s' "$OIDC_JSON" | jq -c '(.Tags // []) | map({(.Key): .Value}) | add // {}' 2>/dev/null || printf '{}')
  HAS_STS=$(printf '%s' "$OIDC_JSON" | jq -r 'if (.ClientIDList // []) | index("sts.amazonaws.com") then "true" else "false" end' 2>/dev/null || printf 'false')

  log_info "GitHub OIDC provider already exists:"
  log_info "  arn                  ${OIDC_ARN}"
  log_info "  trusts sts.amazonaws.com: ${HAS_STS}"
  log_info "  other audiences kept: ${ADDITIONAL_AUDIENCES}"
  log_info "  tags kept:            ${OIDC_TAGS}"

  case "$RB_ExistingOIDCProvider" in
    import)
      OIDC_IMPORT=true
      log_info "Importing it: the stack adopts the provider, and the plan will show the"
      log_info "sts.amazonaws.com audience being added if it is missing."
      ;;
    leave-alone)
      EXCLUDE_OIDC=true
      log_warn "Leaving it alone: the stack omits the OIDC provider entirely."
      if [ "$HAS_STS" != "true" ]; then
        if [ "$RB_AddStsAudienceIfMissing" = "true" ]; then
          log_warn "Adding the sts.amazonaws.com audience directly, since nothing will manage it."
          if aws iam add-client-id-to-open-id-connect-provider \
               --open-id-connect-provider-arn "$OIDC_ARN" --client-id "sts.amazonaws.com"; then
            log_info "Audience added."
          else
            log_error "Could not add the audience. Add it by hand, then run this step again."
            exit 1
          fi
        else
          log_error "This provider does not trust sts.amazonaws.com, nothing here will manage it,"
          log_error "and AddStsAudienceIfMissing is false. Pipelines cannot authenticate this way."
          log_error "Either set ExistingOIDCProvider to import, or set AddStsAudienceIfMissing to"
          log_error "true, or add the audience yourself:"
          log_error "  aws iam add-client-id-to-open-id-connect-provider \\"
          log_error "    --open-id-connect-provider-arn ${OIDC_ARN} --client-id sts.amazonaws.com"
          exit 1
        fi
      fi
      ;;
    *)
      log_error "Unknown ExistingOIDCProvider value [${RB_ExistingOIDCProvider}]."
      exit 1
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Plan and apply roles
# ---------------------------------------------------------------------------

PLAN_ROLE_IMPORT=false;  PLAN_POLICY_IMPORT=false;  PLAN_ATTACH_IMPORT=false
APPLY_ROLE_IMPORT=false; APPLY_POLICY_IMPORT=false; APPLY_ATTACH_IMPORT=false
FOUND_ROLES=""

check_role() {
  role=$1
  policy_arn="arn:${PARTITION}:iam::${ACCOUNT}:policy/${role}"
  role_exists=$(aws_exists "IAM role ${role}" aws iam get-role --role-name "$role") || exit 1
  [ "$role_exists" = "true" ] || { log_info "IAM role ${role}: not present, will be created."; return 0; }

  policy_exists=$(aws_exists "IAM policy ${policy_arn}" aws iam get-policy --policy-arn "$policy_arn") || exit 1
  attach_exists=false
  if [ "$policy_exists" = "true" ]; then
    attach_exists=$(policy_attached "$role" "$policy_arn")
  fi

  FOUND_ROLES="${FOUND_ROLES:+${FOUND_ROLES}, }${role}"
  log_warn "IAM role ${role} already exists  (policy: ${policy_exists}, attached: ${attach_exists})"

  case $role in
    *-plan)  PLAN_ROLE_IMPORT=true;  PLAN_POLICY_IMPORT=$policy_exists;  PLAN_ATTACH_IMPORT=$attach_exists ;;
    *-apply) APPLY_ROLE_IMPORT=true; APPLY_POLICY_IMPORT=$policy_exists; APPLY_ATTACH_IMPORT=$attach_exists ;;
  esac
}

log_info ""
check_role "${PREFIX}-plan"
check_role "${PREFIX}-apply"

if [ -n "$FOUND_ROLES" ]; then
  case "$RB_ExistingPipelinesRoles" in
    import)
      log_warn "Importing ${FOUND_ROLES} into the bootstrap stack."
      log_warn "Any customizations on them are replaced with the bootstrap's own policy documents;"
      log_warn "the plan in the next step shows exactly what changes."
      ;;
    stop)
      log_error "These roles already exist: ${FOUND_ROLES}"
      log_error "ExistingPipelinesRoles is set to stop, so nothing has been generated."
      log_error "Choose a different OIDCResourcePrefix above and run this step again, or set"
      log_error "ExistingPipelinesRoles to import to adopt them into the bootstrap stack."
      exit 1
      ;;
    *)
      log_error "Unknown ExistingPipelinesRoles value [${RB_ExistingPipelinesRoles}]."
      exit 1
      ;;
  esac
else
  log_info "No roles with the prefix ${PREFIX} exist yet; all of them will be created."
fi

{
  echo "oidc_import_existing=${OIDC_IMPORT}"
  echo "exclude_oidc_provider=${EXCLUDE_OIDC}"
  echo "additional_audiences=${ADDITIONAL_AUDIENCES}"
  echo "oidc_provider_tags=${OIDC_TAGS}"
  echo "plan_role_import=${PLAN_ROLE_IMPORT}"
  echo "plan_policy_import=${PLAN_POLICY_IMPORT}"
  echo "plan_attachment_import=${PLAN_ATTACH_IMPORT}"
  echo "apply_role_import=${APPLY_ROLE_IMPORT}"
  echo "apply_policy_import=${APPLY_POLICY_IMPORT}"
  echo "apply_attachment_import=${APPLY_ATTACH_IMPORT}"
} >> "$RUNBOOK_OUTPUT"

log_info ""
log_info "Import plan settled. The generate step will render these into the bootstrap stack."
exit 0
