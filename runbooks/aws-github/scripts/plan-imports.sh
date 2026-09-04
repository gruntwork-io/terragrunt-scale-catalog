#!/bin/bash
# Decide what to do about a GitHub OIDC provider that already exists, and make sure the IAM roles
# this bootstrap is about to create do not collide with roles that are already there.
#
# The provider is the only thing that can be adopted. Roles and policies are always created by the
# bootstrap: adopting them means Terragrunt takes ownership and rewrites them to its own
# configuration, which silently repoints a role that belonged to something else.
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
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
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
# The roles this run will create
# ---------------------------------------------------------------------------

# Since the roles are always created, a role already holding the name is a hard stop: the apply
# would fail on the duplicate, after the configuration had been generated and committed. Caught
# here instead, while changing the prefix still costs nothing.
taken=""
for role in "${PREFIX}-plan" "${PREFIX}-apply"; do
  out=$(aws iam get-role --role-name "$role" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    taken="${taken:+${taken}, }${role}"
  elif ! printf '%s' "$out" | grep -q NoSuchEntity; then
    log_error "Could not check whether ${role} exists: ${out}"
    exit 1
  fi
done

if [ -n "$taken" ]; then
  log_error "These IAM roles already exist in account ${ACCOUNT}: ${taken}"
  log_error "This bootstrap always creates its own roles, so the apply would fail on the duplicate"
  log_error "name. Choose a different OIDCResourcePrefix above and run this step again."
  log_error ""
  log_error "The existing roles are left exactly as they are; nothing here touches them."
  exit 1
fi
log_info "Neither ${PREFIX}-plan nor ${PREFIX}-apply exists yet; both will be created."

# Not a blocker, but worth knowing: another set of roles may already be wired to this repository,
# and two sets both trusting it is rarely intended.
others=$(aws iam list-roles --output json 2>/dev/null | jq -r --arg prov "$OIDC_PROVIDER_ARN" \
  --arg a "repo:${RB_out_clone_repo_owner}@${RB_out_clone_org_id}/${RB_out_clone_repo_name}@${RB_out_clone_repo_id}:" \
  --arg b "repo:${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}:" '
  .Roles[]? as $r
  | ($r.AssumeRolePolicyDocument.Statement // [])[]
  | select((.Action == "sts:AssumeRoleWithWebIdentity") or (.Action[]? == "sts:AssumeRoleWithWebIdentity"))
  | select(.Principal.Federated == $prov)
  | (.Condition // {}) | to_entries[] | .value | to_entries[]
  | select(.key | endswith(":sub"))
  | (if (.value | type) == "array" then .value[] else .value end) as $sub
  | select(($sub | startswith($a)) or ($sub | startswith($b)))
  | $r.RoleName' 2>/dev/null | sort -u | tr '\n' ' ')
if [ -n "${others// /}" ]; then
  log_warn "These roles already trust this repository through the provider: ${others}"
  log_warn "The new ${PREFIX}-plan / ${PREFIX}-apply roles will trust it as well. If the old ones are"
  log_warn "no longer wanted, remove them once Pipelines is running on the new pair."
fi

# ---------------------------------------------------------------------------
# OIDC provider
# ---------------------------------------------------------------------------

# "Absent" has to be distinguished from "could not tell", the way the role check above does. Reading
# a denied call or a throttle as "no provider" would have the bootstrap create a second one, and the
# apply would fail on a duplicate after the configuration was already generated.
OIDC_JSON=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" --output json 2>&1)
oidc_rc=$?
if [ "$oidc_rc" -ne 0 ]; then
  if printf '%s' "$OIDC_JSON" | grep -q NoSuchEntity; then
    OIDC_JSON=""
  else
    log_error "Could not check whether an OIDC provider exists at ${ISSUER_HOST}:"
    log_error "  ${OIDC_JSON}"
    log_error "Treating that as 'no provider' would create a second one and fail the apply, so this"
    log_error "stops here. Check the credentials can read IAM, then run this step again."
    exit 1
  fi
fi
OIDC_IMPORT=false
EXCLUDE_OIDC=false
ADDITIONAL_AUDIENCES="[]"
OIDC_TAGS="{}"

log_info ""
if [ -z "$OIDC_JSON" ]; then
  log_info "No OIDC provider at ${ISSUER_HOST}; the bootstrap will create one."
else
  # The desired state replaces the audience list wholesale, so anything already trusted has to be
  # carried across or the apply would drop it. Same for tags.
  ADDITIONAL_AUDIENCES=$(printf '%s' "$OIDC_JSON" | jq -c '[.ClientIDList[]? | select(. != "sts.amazonaws.com")]' 2>/dev/null || printf '[]')
  OIDC_TAGS=$(printf '%s' "$OIDC_JSON" | jq -c '(.Tags // []) | map({(.Key): .Value}) | add // {}' 2>/dev/null || printf '{}')
  HAS_STS=$(printf '%s' "$OIDC_JSON" | jq -r 'if (.ClientIDList // []) | index("sts.amazonaws.com") then "true" else "false" end' 2>/dev/null || printf 'false')

  log_info "An OIDC provider already exists:"
  log_info "  arn                       ${OIDC_PROVIDER_ARN}"
  log_info "  trusts sts.amazonaws.com  ${HAS_STS}"
  log_info "  other audiences kept      ${ADDITIONAL_AUDIENCES}"
  log_info "  tags kept                 ${OIDC_TAGS}"

  case "$RB_ExistingOIDCProvider" in
    import)
      OIDC_IMPORT=true
      log_info "Importing it: the stack adopts the provider, and the plan will show the"
      log_info "sts.amazonaws.com audience being added if it is missing."
      ;;
    leave-alone)
      EXCLUDE_OIDC=true
      log_warn "Leaving it alone: the stack omits the OIDC provider entirely. The new roles will"
      log_warn "trust it, but nothing here manages it."
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
          log_error "This provider does not trust sts.amazonaws.com and nothing here will manage it,"
          log_error "so Pipelines could not authenticate. Set ExistingOIDCProvider to import, or"
          log_error "AddStsAudienceIfMissing to true, or run:"
          log_error "  aws iam add-client-id-to-open-id-connect-provider \\"
          log_error "    --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN} --client-id sts.amazonaws.com"
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

{
  echo "oidc_import_existing=${OIDC_IMPORT}"
  echo "exclude_oidc_provider=${EXCLUDE_OIDC}"
  echo "additional_audiences=${ADDITIONAL_AUDIENCES}"
  echo "oidc_provider_tags=${OIDC_TAGS}"
} >> "$RUNBOOK_OUTPUT"

log_info ""
log_info "Ready to generate. The IAM roles and policies will be created fresh."
exit 0
