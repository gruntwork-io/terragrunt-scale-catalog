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
RB_Issuer=$(rb_unquote "{{ .inputs.Issuer }}")
RB_ExistingPipelinesRoles=$(rb_unquote "{{ .inputs.ExistingPipelinesRoles }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_out_read_details_aws_account_id=$(rb_unquote "{{ .outputs.read_details.aws_account_id }}")
RB_out_read_details_partition=$(rb_unquote "{{ .outputs.read_details.partition }}")
RB_out_clone_org_id=$(rb_unquote "{{ .outputs.clone.org_id }}")
RB_out_clone_repo_id=$(rb_unquote "{{ .outputs.clone.repo_id }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")

ACCOUNT="$RB_out_read_details_aws_account_id"
PARTITION="$RB_out_read_details_partition"
PREFIX="$RB_OIDCResourcePrefix"

# An OIDC provider has no name: it is addressed by its issuer host, so that is what decides which
# provider is looked for, imported and trusted. GitHub Enterprise Server and enterprises with unique
# token URLs use a different one, and then every ARN below has to follow it.
if [ "$RB_Issuer" = "default" ] || [ -z "$RB_Issuer" ]; then
  RB_Issuer=""
  ISSUER_HOST="token.actions.githubusercontent.com"
else
  ISSUER_HOST=${RB_Issuer#https://}
  ISSUER_HOST=${ISSUER_HOST#http://}
  ISSUER_HOST=${ISSUER_HOST%/}
  log_info "Using a non-default OIDC issuer: ${RB_Issuer}"
fi
OIDC_PROVIDER_ARN="arn:${PARTITION}:iam::${ACCOUNT}:oidc-provider/${ISSUER_HOST}"

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

# The iam-policy module names its policies "<name>-<first 8 of sha256(document)>"
# (modules/aws/iam-policy/main.tf), so the plain "<prefix>-plan" ARN never exists and cannot be
# probed for. The authoritative place to find the real one is the role it is attached to; failing
# that, the account's customer-managed policies. The stack recomputes the same hash when it builds
# the import ARN, so all this has to establish is whether one is there.
#
# Sets: FOUND_POLICY_ARN (empty when none), FOUND_POLICY_ATTACHED (true/false)
find_policy_for_role() {
  local role=$1 json
  FOUND_POLICY_ARN=""
  FOUND_POLICY_ATTACHED=false

  json=$(aws iam list-attached-role-policies --role-name "$role" --output json 2>/dev/null) || json=""
  if [ -n "$json" ]; then
    FOUND_POLICY_ARN=$(printf '%s' "$json" \
      | jq -r --arg re "^${role}-[0-9a-f]{8}$" \
          'first(.AttachedPolicies[]? | select(.PolicyName | test($re)) | .PolicyArn) // ""' 2>/dev/null)
    if [ -n "$FOUND_POLICY_ARN" ]; then
      FOUND_POLICY_ATTACHED=true
      return 0
    fi
  fi

  # Not attached anywhere, but a policy of that shape may still be sitting in the account and would
  # collide on create if the document hashes the same.
  json=$(aws iam list-policies --scope Local --output json 2>/dev/null) || json=""
  [ -n "$json" ] || return 0
  FOUND_POLICY_ARN=$(printf '%s' "$json" \
    | jq -r --arg re "^${role}-[0-9a-f]{8}$" \
        'first(.Policies[]? | select(.PolicyName | test($re)) | .Arn) // ""' 2>/dev/null)
}

# Whether an existing role is this repository's own Pipelines role. Importing rewrites the trust
# policy, so adopting a role that belongs to somewhere else silently takes it over.
#
# Returns: 0 this repository, 1 a GitHub OIDC role for a different repository, 2 not an OIDC role
role_belongs_to_this_repo() {
  local role=$1 doc subs provider_arn
  provider_arn="$OIDC_PROVIDER_ARN"

  doc=$(aws iam get-role --role-name "$role" --output json 2>/dev/null \
    | jq -c '.Role.AssumeRolePolicyDocument' 2>/dev/null) || doc=""
  [ -n "$doc" ] && [ "$doc" != "null" ] || return 2

  printf '%s' "$doc" | jq -e --arg p "$provider_arn" '
    any(.Statement[]?;
      (.Action == "sts:AssumeRoleWithWebIdentity" or (.Action[]? == "sts:AssumeRoleWithWebIdentity"))
      and (.Principal.Federated == $p))' >/dev/null 2>&1 || return 2

  # Both sub formats: the immutable "owner@orgid/repo@repoid" one and the older "owner/repo".
  subs=$(printf '%s' "$doc" | jq -r '
    [.Statement[]?.Condition // {} | .[] | to_entries[]
     | select(.key | endswith(":sub")) | .value] | flatten | join(" ")' 2>/dev/null)

  case "$subs" in
    *"repo:${RB_out_clone_repo_owner}@${RB_out_clone_org_id}/${RB_out_clone_repo_name}@${RB_out_clone_repo_id}:"*) return 0 ;;
    *"repo:${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}:"*) return 0 ;;
  esac
  FOREIGN_SUB="$subs"
  return 1
}

# ---------------------------------------------------------------------------
# OIDC provider
# ---------------------------------------------------------------------------

OIDC_ARN="$OIDC_PROVIDER_ARN"
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

FOREIGN_ROLES=""
NOT_OIDC_ROLES=""

check_role() {
  role=$1
  role_exists=$(aws_exists "IAM role ${role}" aws iam get-role --role-name "$role") || exit 1
  [ "$role_exists" = "true" ] || { log_info "IAM role ${role}: not present, will be created."; return 0; }

  FOUND_ROLES="${FOUND_ROLES:+${FOUND_ROLES}, }${role}"

  # Who does it currently trust?
  FOREIGN_SUB=""
  belongs=0
  role_belongs_to_this_repo "$role" || belongs=$?
  case $belongs in
    0) log_warn "IAM role ${role} already exists and already trusts this repository." ;;
    1) log_warn "IAM role ${role} already exists but trusts a DIFFERENT repository:"
       log_warn "  ${FOREIGN_SUB}"
       FOREIGN_ROLES="${FOREIGN_ROLES:+${FOREIGN_ROLES}, }${role}" ;;
    2) log_warn "IAM role ${role} already exists but is not a GitHub OIDC role."
       NOT_OIDC_ROLES="${NOT_OIDC_ROLES:+${NOT_OIDC_ROLES}, }${role}" ;;
  esac

  find_policy_for_role "$role"
  policy_exists=false
  [ -n "$FOUND_POLICY_ARN" ] && policy_exists=true
  if [ "$policy_exists" = "true" ]; then
    log_warn "  policy ${FOUND_POLICY_ARN} (attached: ${FOUND_POLICY_ATTACHED})"
  else
    log_info "  no matching policy in the account; one will be created."
  fi

  case $role in
    *-plan)  PLAN_ROLE_IMPORT=true;  PLAN_POLICY_IMPORT=$policy_exists;  PLAN_ATTACH_IMPORT=$FOUND_POLICY_ATTACHED ;;
    *-apply) APPLY_ROLE_IMPORT=true; APPLY_POLICY_IMPORT=$policy_exists; APPLY_ATTACH_IMPORT=$FOUND_POLICY_ATTACHED ;;
  esac
}

log_info ""
check_role "${PREFIX}-plan"
check_role "${PREFIX}-apply"

if [ -n "$FOUND_ROLES" ]; then
  # A role that is not a GitHub OIDC role at all is never adopted, whatever was chosen: importing
  # rewrites its trust policy, which would break whatever does use it.
  if [ -n "$NOT_OIDC_ROLES" ]; then
    log_error "These roles exist but are not GitHub OIDC roles: ${NOT_OIDC_ROLES}"
    log_error "Importing one would replace its trust policy and break whatever relies on it."
    log_error "Choose a different OIDCResourcePrefix above and run this step again."
    exit 1
  fi

  case "$RB_ExistingPipelinesRoles" in
    import)
      if [ -n "$FOREIGN_ROLES" ]; then
        log_error "These roles belong to a different repository: ${FOREIGN_ROLES}"
        log_error "Importing them repoints their trust policy at this repository, which stops"
        log_error "Pipelines working for the repository that has them today."
        log_error "Either choose a different OIDCResourcePrefix above, or set"
        log_error "ExistingPipelinesRoles to import-any if taking them over is what you intend."
        exit 1
      fi
      log_warn "Importing ${FOUND_ROLES} into the bootstrap stack."
      log_warn "Any customizations on them are replaced with the bootstrap's own policy documents;"
      log_warn "the plan in the next step shows exactly what changes."
      ;;
    import-any)
      log_warn "Importing ${FOUND_ROLES} into the bootstrap stack."
      if [ -n "$FOREIGN_ROLES" ]; then
        log_warn "TAKING OVER ${FOREIGN_ROLES} from another repository, as asked. That repository's"
        log_warn "Pipelines stops working once this is applied."
      fi
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
