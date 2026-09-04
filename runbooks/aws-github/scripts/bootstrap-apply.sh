#!/bin/bash
# Apply the bootstrap stack. This creates real AWS resources (OIDC provider + IAM roles)
# and the S3 state bucket. Review the plan output above before running this.
set -euo pipefail

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

RB_AccountName=$(rb_unquote "{{ .inputs.AccountName }}")
RB_out_read_details_aws_account_id=$(rb_unquote "{{ .outputs.read_details.aws_account_id }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_out_read_details_partition=$(rb_unquote "{{ .outputs.read_details.partition }}")
RB_out_read_details_deploy_branch=$(rb_unquote "{{ .outputs.read_details.deploy_branch }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Temporary AWS credentials routinely expire part-way through this runbook — it is long, and the
# gap between steps is however long you were away. Check reachability first so an expired session
# says so plainly here, instead of surfacing as a confusing failure further in.
if ! aws_account=$(aws sts get-caller-identity --output text --query 'Account' 2>&1); then
  log_error "Could not reach AWS with the current credentials: ${aws_account}"
  log_error "Re-run the AWS authentication step above to refresh them, then run this step again."
  exit 1
fi
log_info "Authenticated to AWS account ${aws_account}."

cd "$REPO_FILES/${RB_AccountName}/_global/bootstrap"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply IAM roles now exist in account ${RB_out_read_details_aws_account_id}."

# ---------------------------------------------------------------------------
# What the apply just created
# ---------------------------------------------------------------------------

# Folded in from what used to be a separate block, because there is nothing to decide in between:
# the apply either succeeded and there are resources to show, or `set -e` already stopped the script.
# The app has no way to chain one block onto another, so one script is what makes it one click.
#
# A subshell function, so the listing keeps `set -uo pipefail` (deliberately without -e, to report
# every gap instead of stopping at the first) without changing the apply's own error handling.
show_resources() (
PREFIX="$RB_OIDCResourcePrefix"
ACCOUNT="$RB_out_read_details_aws_account_id"
PARTITION="$RB_out_read_details_partition"
# The stack uses GitHub's OIDC issuer unless one was overridden, which this runbook does not do.
ISSUER_HOST="token.actions.githubusercontent.com"

missing=0

# Filled in by the lookups below and used to label the diagram.
OIDC_AUDIENCES=""
LAST_ROLE_ARN=""
LAST_ROLE_POLICY_ARN=""
LAST_ROLE_POLICY_NAME=""
PLAN_ROLE_ARN=""
APPLY_ROLE_ARN=""
PLAN_POLICY_ARN=""
APPLY_POLICY_ARN=""
PLAN_POLICY_NAME=""
APPLY_POLICY_NAME=""

show_oidc_provider() {
  local arn json audiences created
  arn="arn:${PARTITION}:iam::${ACCOUNT}:oidc-provider/${ISSUER_HOST}"
  json=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --output json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "OIDC provider ${ISSUER_HOST}: not found"
    missing=$((missing + 1))
    return
  fi
  audiences=$(printf '%s' "$json" | jq -r '.ClientIDList | join(", ")' 2>/dev/null)
  OIDC_AUDIENCES="$audiences"
  created=$(printf '%s' "$json" | jq -r '.CreateDate // "unknown"' 2>/dev/null)
  log_info "OIDC provider"
  log_info "  url        ${ISSUER_HOST}"
  log_info "  arn        ${arn}"
  log_info "  audiences  ${audiences:-<none>}"
  log_info "  created    ${created}"
}

show_role() {
  local name=$1 label=$2 json arn created policies inline attached
  json=$(aws iam get-role --role-name "$name" --output json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "${label} role ${name}: not found"
    missing=$((missing + 1))
    return
  fi
  arn=$(printf '%s' "$json" | jq -r '.Role.Arn' 2>/dev/null)
  LAST_ROLE_ARN="$arn"
  created=$(printf '%s' "$json" | jq -r '.Role.CreateDate // "unknown"' 2>/dev/null)
  log_info "${label} role"
  log_info "  name       ${name}"
  log_info "  arn        ${arn}"
  log_info "  created    ${created}"

  policies=$(aws iam list-attached-role-policies --role-name "$name" --output json 2>/dev/null \
    | jq -r '.AttachedPolicies[].PolicyArn' 2>/dev/null)
  if [ -n "$policies" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && log_info "  policy     ${p}"
    done <<< "$policies"
    # Kept for the diagram and the account README. The catalog attaches exactly one policy per role,
    # named "<prefix>-<kind>-<sha256(document)[:8]>", so the first is the one to show. A role that
    # has picked up others is reported as a count rather than as a misleadingly single name.
    LAST_ROLE_POLICY_ARN=$(printf '%s\n' "$policies" | head -1)
    LAST_ROLE_POLICY_NAME=${LAST_ROLE_POLICY_ARN##*/}
    attached=$(printf '%s\n' "$policies" | grep -c .)
    if [ "$attached" -gt 1 ]; then
      LAST_ROLE_POLICY_NAME="${LAST_ROLE_POLICY_NAME} (+$((attached - 1)) more)"
    fi
  else
    LAST_ROLE_POLICY_NAME="(none attached)"
  fi

  inline=$(aws iam list-role-policies --role-name "$name" --output json 2>/dev/null \
    | jq -r '.PolicyNames[]' 2>/dev/null)
  if [ -n "$inline" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && log_info "  inline     ${p}"
    done <<< "$inline"
  fi
}

show_state_bucket() {
  local region versioning encryption
  if ! aws s3api head-bucket --bucket "$RB_StateBucketName" >/dev/null 2>&1; then
    log_warn "State bucket ${RB_StateBucketName}: not found (or not reachable with these credentials)"
    missing=$((missing + 1))
    return
  fi
  region=$(aws s3api get-bucket-location --bucket "$RB_StateBucketName" --output json 2>/dev/null \
    | jq -r '.LocationConstraint // "us-east-1"' 2>/dev/null)
  versioning=$(aws s3api get-bucket-versioning --bucket "$RB_StateBucketName" --output json 2>/dev/null \
    | jq -r '.Status // "Disabled"' 2>/dev/null)
  encryption=$(aws s3api get-bucket-encryption --bucket "$RB_StateBucketName" --output json 2>/dev/null \
    | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm // "none"' 2>/dev/null)
  log_info "State bucket"
  log_info "  name       ${RB_StateBucketName}"
  log_info "  arn        arn:${PARTITION}:s3:::${RB_StateBucketName}"
  log_info "  region     ${region}"
  log_info "  versioning ${versioning}"
  log_info "  encryption ${encryption}"
}

log_info "Reading back what the bootstrap created in account ${ACCOUNT}..."
log_info ""
show_oidc_provider
log_info ""
LAST_ROLE_ARN=""; LAST_ROLE_POLICY_ARN=""; LAST_ROLE_POLICY_NAME=""
show_role "${PREFIX}-plan" "Plan"
PLAN_ROLE_ARN="$LAST_ROLE_ARN"
PLAN_POLICY_ARN="$LAST_ROLE_POLICY_ARN"
PLAN_POLICY_NAME="$LAST_ROLE_POLICY_NAME"
log_info ""
LAST_ROLE_ARN=""; LAST_ROLE_POLICY_ARN=""; LAST_ROLE_POLICY_NAME=""
show_role "${PREFIX}-apply" "Apply"
APPLY_ROLE_ARN="$LAST_ROLE_ARN"
APPLY_POLICY_ARN="$LAST_ROLE_POLICY_ARN"
APPLY_POLICY_NAME="$LAST_ROLE_POLICY_NAME"
log_info ""
show_state_bucket
log_info ""

# ---------------------------------------------------------------------------
# Diagram
# ---------------------------------------------------------------------------

# The right-hand panel renders any .svg in the repository as an image, so the topology this
# bootstrap just created is written as a committed document rather than only described in the log.
#
# ASCII only, deliberately: the preview does btoa(svgText), which throws on any character above
# U+00FF and then silently renders nothing. No dashes other than "-", no arrows, no smart quotes.
#
# No timestamp either: re-running produces a byte-identical file unless the resources actually
# changed, which keeps it out of diffs and makes the before/after preview meaningful.
svg_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

write_diagram() {
  local dir="$REPO_FILES/${RB_AccountName}" file="$REPO_FILES/${RB_AccountName}/pipelines-bootstrap.svg"
  mkdir -p "$dir" || { log_warn "Could not create ${dir}; skipping the diagram."; return 0; }

  # The box fits roughly 78 characters at this font size; clip rather than overflow it.
  local repo_label="${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}"
  if [ "${#repo_label}" -gt 78 ]; then
    repo_label="$(printf '%s' "$repo_label" | cut -c1-75)..."
  fi

  cat > "$file" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="600" viewBox="0 0 760 600" font-family="Helvetica, Arial, sans-serif">
  <rect width="760" height="600" fill="#ffffff"/>
  <text x="380" y="34" text-anchor="middle" font-size="17" font-weight="bold" fill="#1a1a1a">Gruntwork Pipelines bootstrap</text>
  <text x="380" y="54" text-anchor="middle" font-size="12" fill="#666666">AWS account __RB_ACCOUNT__ (__RB_PARTITION__)</text>

  <rect x="130" y="80" width="500" height="62" rx="6" fill="#f4f6f8" stroke="#5b6b7c" stroke-width="1.5"/>
  <text x="380" y="103" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GitHub Actions</text>
  <text x="380" y="121" text-anchor="middle" font-size="11" fill="#444444">__RB_REPO__</text>
  <text x="380" y="136" text-anchor="middle" font-size="11" fill="#444444">deploy branch: __RB_BRANCH__</text>

  <line x1="380" y1="142" x2="380" y2="182" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="392" y="167" font-size="10" fill="#666666">OIDC token</text>

  <rect x="190" y="182" width="380" height="66" rx="6" fill="#fdf3e3" stroke="#c98a1b" stroke-width="1.5"/>
  <text x="380" y="205" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">IAM OIDC provider</text>
  <text x="380" y="223" text-anchor="middle" font-size="11" fill="#444444">__RB_ISSUER__</text>
  <text x="380" y="239" text-anchor="middle" font-size="11" fill="#444444">audience: __RB_AUDIENCE__</text>

  <line x1="300" y1="248" x2="190" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="460" y1="248" x2="570" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="20" y="304" width="350" height="86" rx="6" fill="#eef5ee" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan role</text>
  <text x="195" y="346" text-anchor="middle" font-size="10" fill="#444444">__RB_PLAN_ARN__</text>
  <text x="195" y="364" text-anchor="middle" font-size="10" fill="#666666">assumed on pull requests</text>
  <text x="195" y="380" text-anchor="middle" font-size="10" fill="#666666">read only</text>

  <rect x="390" y="304" width="350" height="86" rx="6" fill="#fdeeee" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply role</text>
  <text x="565" y="346" text-anchor="middle" font-size="10" fill="#444444">__RB_APPLY_ARN__</text>
  <text x="565" y="364" text-anchor="middle" font-size="10" fill="#666666">assumed on merges to __RB_BRANCH__</text>
  <text x="565" y="380" text-anchor="middle" font-size="10" fill="#666666">creates and changes infrastructure</text>

  <line x1="195" y1="390" x2="195" y2="416" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="203" y="408" font-size="9" fill="#666666">attached</text>
  <line x1="565" y1="390" x2="565" y2="416" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="573" y="408" font-size="9" fill="#666666">attached</text>

  <rect x="20" y="420" width="350" height="66" rx="6" fill="#f7faf7" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="443" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan policy</text>
  <text x="195" y="462" text-anchor="middle" font-size="10" fill="#444444">__RB_PLAN_POLICY__</text>
  <text x="195" y="478" text-anchor="middle" font-size="10" fill="#666666">from plan_iam_policy.json</text>

  <rect x="390" y="420" width="350" height="66" rx="6" fill="#fdf7f7" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="443" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply policy</text>
  <text x="565" y="462" text-anchor="middle" font-size="10" fill="#444444">__RB_APPLY_POLICY__</text>
  <text x="565" y="478" text-anchor="middle" font-size="10" fill="#666666">from apply_iam_policy.json</text>

  <line x1="195" y1="486" x2="330" y2="514" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="565" y1="486" x2="430" y2="514" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="210" y="518" width="340" height="66" rx="6" fill="#eef2f8" stroke="#3f5f8d" stroke-width="1.5"/>
  <text x="380" y="541" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">S3 state bucket</text>
  <text x="380" y="559" text-anchor="middle" font-size="11" fill="#444444">__RB_BUCKET__</text>
  <text x="380" y="575" text-anchor="middle" font-size="10" fill="#666666">OpenTofu / Terraform state</text>

  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/>
    </marker>
  </defs>
</svg>
SVGEOF

  sed -i.bak \
    -e "s|__RB_ACCOUNT__|$(svg_escape "$ACCOUNT")|g" \
    -e "s|__RB_PARTITION__|$(svg_escape "$PARTITION")|g" \
    -e "s|__RB_REPO__|$(svg_escape "$repo_label")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_ISSUER__|$(svg_escape "$ISSUER_HOST")|g" \
    -e "s|__RB_AUDIENCE__|$(svg_escape "${OIDC_AUDIENCES:-sts.amazonaws.com}")|g" \
    -e "s|__RB_PLAN_ARN__|$(svg_escape "$PLAN_ROLE_ARN")|g" \
    -e "s|__RB_APPLY_ARN__|$(svg_escape "$APPLY_ROLE_ARN")|g" \
    -e "s|__RB_PLAN_POLICY__|$(svg_escape "${PLAN_POLICY_NAME:-(none attached)}")|g" \
    -e "s|__RB_APPLY_POLICY__|$(svg_escape "${APPLY_POLICY_NAME:-(none attached)}")|g" \
    -e "s|__RB_BUCKET__|$(svg_escape "$RB_StateBucketName")|g" \
    "$file"
  rm -f "$file.bak"

  if grep -q '__RB_' "$file"; then
    log_warn "The diagram still has unsubstituted placeholders; wrote it anyway at ${RB_AccountName}/pipelines-bootstrap.svg."
  else
    log_info "Wrote ${RB_AccountName}/pipelines-bootstrap.svg (shown as an image in the Changed files panel)."
  fi
}

# Each account bootstrapped into this repository gets its own diagram and its own README, because
# every account has its own roles, bucket and account ID. A root-level document would be overwritten
# by the next account.
#
# An existing README in that folder is never overwritten, whoever wrote it: the generated document
# is written alongside it as README.template.md instead.

# A README that is still a stub — a heading, maybe a one-line description, nothing else — carries no
# information worth keeping. Anything with real structure (sections, code, lists, links, tables) is
# somebody's work and is never touched. Same rule the root README follows.
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

write_account_readme() {
  local dir="$REPO_FILES/${RB_AccountName}" doc target title=""
  doc="$dir/README.md"
  target="$doc"

  # The same outcomes the root README uses, so nothing a human wrote is ever lost:
  #   a stub     -> replace it, keeping whatever title was there
  #   anything else, including a README this runbook wrote and someone has since edited
  #              -> leave it alone and write the generated document alongside it
  if [ -f "$doc" ]; then
    if readme_is_stub "$doc"; then
      log_warn "${RB_AccountName}/README.md is still a stub; replacing it."
      title=$(head -1 "$doc" | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    else
      target="$dir/README.template.md"
      log_info "${RB_AccountName}/README.md already exists and has real content; leaving it untouched."
      log_info "Writing the generated documentation to ${RB_AccountName}/README.template.md instead."
    fi
  fi
  [ -n "$title" ] || title="${RB_AccountName}"

  cat > "$target" <<'MDEOF'
# __RB_TITLE__

Gruntwork Pipelines is bootstrapped for this environment in AWS account `__RB_ACCOUNT__`.

![What the bootstrap provisioned](pipelines-bootstrap.svg)

## Identifiers

| | |
|---|---|
| AWS account | `__RB_ACCOUNT__` |
| Partition | `__RB_PARTITION__` |
| Deploy branch | `__RB_BRANCH__` |
| OIDC provider | `__RB_OIDC_ARN__` |
| Plan role | `__RB_PLAN_ARN__` |
| Plan policy | `__RB_PLAN_POLICY_ARN__` |
| Apply role | `__RB_APPLY_ARN__` |
| Apply policy | `__RB_APPLY_POLICY_ARN__` |
| State bucket | `__RB_BUCKET__` |

## How this account is deployed

Pipelines assumes the plan role on pull requests and the apply role on merges to
`__RB_BRANCH__`, for changes under `__RB_ACCOUNT_NAME__/`. The bootstrap stack that created these
resources is in `__RB_ACCOUNT_NAME__/_global/bootstrap`.

## What those roles may do

Two documents in `__RB_ACCOUNT_NAME__/_global/bootstrap/` define the permissions:

| | |
|---|---|
| `plan_iam_policy.json` | Attached to the plan role |
| `apply_iam_policy.json` | Attached to the apply role |

They are ordinary IAM policy documents, written from the Terragrunt Scale catalog defaults when this
account was bootstrapped. Edit one, open a pull request, and the plan names exactly which permissions
change. The stack reads these files rather than the catalog's own copies, so upgrading the catalog
ref will not alter them.

The state bucket name is written into them literally. If `__RB_BUCKET__` is ever renamed, update
both documents to match, or the plan role loses access to state.

MDEOF

  sed -i.bak \
    -e "s|__RB_ACCOUNT_NAME__|$(svg_escape "$RB_AccountName")|g" \
    -e "s|__RB_ACCOUNT__|$(svg_escape "$ACCOUNT")|g" \
    -e "s|__RB_PARTITION__|$(svg_escape "$PARTITION")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_OIDC_ARN__|$(svg_escape "arn:${PARTITION}:iam::${ACCOUNT}:oidc-provider/${ISSUER_HOST}")|g" \
    -e "s|__RB_PLAN_ARN__|$(svg_escape "$PLAN_ROLE_ARN")|g" \
    -e "s|__RB_APPLY_ARN__|$(svg_escape "$APPLY_ROLE_ARN")|g" \
    -e "s|__RB_BUCKET__|$(svg_escape "$RB_StateBucketName")|g" \
    -e "s|__RB_PLAN_POLICY_ARN__|$(svg_escape "${PLAN_POLICY_ARN:-(none attached)}")|g" \
    -e "s|__RB_APPLY_POLICY_ARN__|$(svg_escape "${APPLY_POLICY_ARN:-(none attached)}")|g" \
    -e "s|__RB_TITLE__|$(svg_escape "$title")|g" \
    "$target"
  rm -f "$target.bak"

  # A failed substitution must not be reported as success: check the result, do not assume it.
  if grep -q '__RB_' "$target"; then
    log_warn "$(basename "$target") still has unsubstituted placeholders; check the values above."
  else
    log_info "Wrote ${RB_AccountName}/$(basename "$target") documenting this account."
  fi
}

# Only draw it when every resource was read back. A diagram with blank labels would be committed
# into the pull request and would misrepresent the account, which is worse than no diagram.
if [ "$missing" -gt 0 ]; then
  log_warn "Skipping the diagram: not every resource could be read back."
elif [ -z "${REPO_FILES:-}" ]; then
  log_warn "No repository checkout available; skipping the diagram."
else
  write_diagram
  write_account_readme
fi

log_info ""
if [ "$missing" -gt 0 ]; then
  log_warn "${missing} expected resource(s) could not be read back. If the apply above succeeded,"
  log_warn "check that these credentials can read IAM and S3 in account ${ACCOUNT}."
  exit 2
fi

log_info "All bootstrap resources are present in account ${ACCOUNT}."
exit 0
)

set +e
show_resources
rc=$?
set -e

# rc 2 means the apply worked but something could not be read back afterwards -- a warning, not a
# failure, and the runbook's own convention for exactly that.
exit "$rc"
