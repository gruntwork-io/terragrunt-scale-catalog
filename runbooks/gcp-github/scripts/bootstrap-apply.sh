#!/bin/bash
# Apply the bootstrap stack. This creates real GCP resources (Workload Identity Pool/Provider and the
# plan/apply service accounts) and the GCS state bucket. Review the plan output above before running this.
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

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
RB_out_check_gcp_auth_gcp_authenticated=$(rb_unquote "{{ .outputs.check_gcp_auth.gcp_authenticated }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_out_read_details_gcp_project_number=$(rb_unquote "{{ .outputs.read_details.gcp_project_number }}")
RB_out_read_details_deploy_branch=$(rb_unquote "{{ .outputs.read_details.deploy_branch }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Ordering guard: enabled only after GCP authentication is confirmed.
GCP_AUTH="${RB_out_check_gcp_auth_gcp_authenticated}"
log_info "Applying the bootstrap stack (GCP auth confirmed: ${GCP_AUTH})..."

cd "$REPO_FILES/${RB_ProjectName}/bootstrap"

terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply service accounts now exist in project ${RB_GCPProjectID}."

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
PROJECT="$RB_GCPProjectID"
PROJECT_NUMBER="$RB_out_read_details_gcp_project_number"
PREFIX="$RB_OIDCResourcePrefix"
# The stack derives both from the OIDC prefix unless overridden, which this runbook does not do.
POOL="${PREFIX}-pool"
PROVIDER="${PREFIX}-provider"

missing=0

# Filled in by the lookups below and used to label the diagram.
PROVIDER_ISSUER=""

show_pool() {
  local json state display
  json=$(gcloud iam workload-identity-pools describe "$POOL" \
    --location=global --project "$PROJECT" --format=json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "Workload Identity Pool ${POOL}: not found"
    missing=$((missing + 1))
    return
  fi
  state=$(printf '%s' "$json" | jq -r '.state // "unknown"' 2>/dev/null)
  display=$(printf '%s' "$json" | jq -r '.displayName // ""' 2>/dev/null)
  log_info "Workload Identity Pool"
  log_info "  id         ${POOL}"
  log_info "  name       projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}"
  [ -n "$display" ] && log_info "  display    ${display}"
  log_info "  state      ${state}"
}

show_provider() {
  local json issuer state
  json=$(gcloud iam workload-identity-pools providers describe "$PROVIDER" \
    --workload-identity-pool="$POOL" --location=global --project "$PROJECT" --format=json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "Workload Identity Pool provider ${PROVIDER}: not found"
    missing=$((missing + 1))
    return
  fi
  issuer=$(printf '%s' "$json" | jq -r '.oidc.issuerUri // "unknown"' 2>/dev/null)
  PROVIDER_ISSUER="$issuer"
  state=$(printf '%s' "$json" | jq -r '.state // "unknown"' 2>/dev/null)
  log_info "Workload Identity Pool provider"
  log_info "  id         ${PROVIDER}"
  log_info "  issuer     ${issuer}"
  log_info "  state      ${state}"
}

show_service_account() {
  local name=$1 label=$2 email json unique disabled
  email="${name}@${PROJECT}.iam.gserviceaccount.com"
  json=$(gcloud iam service-accounts describe "$email" --project "$PROJECT" --format=json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "${label} service account ${email}: not found"
    missing=$((missing + 1))
    return
  fi
  unique=$(printf '%s' "$json" | jq -r '.uniqueId // "unknown"' 2>/dev/null)
  disabled=$(printf '%s' "$json" | jq -r 'if .disabled then "yes" else "no" end' 2>/dev/null)
  log_info "${label} service account"
  log_info "  email      ${email}"
  log_info "  unique id  ${unique}"
  log_info "  disabled   ${disabled}"
}

show_state_bucket() {
  local json location storage_class versioning
  json=$(gcloud storage buckets describe "gs://${RB_StateBucketName}" --format=json 2>/dev/null)
  if [ -z "$json" ]; then
    log_warn "State bucket gs://${RB_StateBucketName}: not found (or not readable with these credentials)"
    missing=$((missing + 1))
    return
  fi
  location=$(printf '%s' "$json" | jq -r '.location // "unknown"' 2>/dev/null)
  storage_class=$(printf '%s' "$json" | jq -r '.storage_class // .storageClass // "unknown"' 2>/dev/null)
  versioning=$(printf '%s' "$json" | jq -r 'if (.versioning_enabled // .versioning.enabled) then "Enabled" else "Disabled" end' 2>/dev/null)
  log_info "State bucket"
  log_info "  name       gs://${RB_StateBucketName}"
  log_info "  location   ${location}"
  log_info "  class      ${storage_class}"
  log_info "  versioning ${versioning}"
}

log_info "Reading back what the bootstrap created in project ${PROJECT} (${PROJECT_NUMBER})..."
log_info ""
show_pool
log_info ""
show_provider
log_info ""
show_service_account "${PREFIX}-plan" "Plan"
log_info ""
show_service_account "${PREFIX}-apply" "Apply"
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

clip() {
  local s=$1 n=$2
  if [ "${#s}" -gt "$n" ]; then
    printf '%s...' "$(printf '%s' "$s" | cut -c1-$((n - 3)))"
  else
    printf '%s' "$s"
  fi
}

write_diagram() {
  local dir="$REPO_FILES/${RB_ProjectName}" file="$REPO_FILES/${RB_ProjectName}/pipelines-bootstrap.svg"
  mkdir -p "$dir" || { log_warn "Could not create ${dir}; skipping the diagram."; return 0; }

  local repo_label plan_label apply_label
  repo_label=$(clip "${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}" 78)
  plan_label=$(clip "${PREFIX}-plan@${PROJECT}.iam.gserviceaccount.com" 60)
  apply_label=$(clip "${PREFIX}-apply@${PROJECT}.iam.gserviceaccount.com" 60)

  cat > "$file" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="556" viewBox="0 0 760 556" font-family="Helvetica, Arial, sans-serif">
  <rect width="760" height="556" fill="#ffffff"/>
  <text x="380" y="34" text-anchor="middle" font-size="17" font-weight="bold" fill="#1a1a1a">Gruntwork Pipelines bootstrap</text>
  <text x="380" y="54" text-anchor="middle" font-size="12" fill="#666666">GCP project __RB_PROJECT__ (__RB_PROJECT_NUMBER__)</text>

  <rect x="130" y="80" width="500" height="62" rx="6" fill="#f4f6f8" stroke="#5b6b7c" stroke-width="1.5"/>
  <text x="380" y="103" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GitHub Actions</text>
  <text x="380" y="121" text-anchor="middle" font-size="11" fill="#444444">__RB_REPO__</text>
  <text x="380" y="136" text-anchor="middle" font-size="11" fill="#444444">deploy branch: __RB_BRANCH__</text>

  <line x1="380" y1="142" x2="380" y2="182" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="392" y="167" font-size="10" fill="#666666">OIDC token</text>

  <rect x="150" y="182" width="460" height="82" rx="6" fill="#fdf3e3" stroke="#c98a1b" stroke-width="1.5"/>
  <text x="380" y="205" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Workload Identity Federation</text>
  <text x="380" y="223" text-anchor="middle" font-size="11" fill="#444444">pool: __RB_POOL__</text>
  <text x="380" y="239" text-anchor="middle" font-size="11" fill="#444444">provider: __RB_PROVIDER__</text>
  <text x="380" y="255" text-anchor="middle" font-size="10" fill="#666666">__RB_ISSUER__</text>

  <line x1="300" y1="264" x2="190" y2="316" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="460" y1="264" x2="570" y2="316" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="20" y="320" width="350" height="86" rx="6" fill="#eef5ee" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="343" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan service account</text>
  <text x="195" y="362" text-anchor="middle" font-size="10" fill="#444444">__RB_PLAN_SA__</text>
  <text x="195" y="380" text-anchor="middle" font-size="10" fill="#666666">impersonated on pull requests</text>
  <text x="195" y="396" text-anchor="middle" font-size="10" fill="#666666">read only</text>

  <rect x="390" y="320" width="350" height="86" rx="6" fill="#fdeeee" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="343" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply service account</text>
  <text x="565" y="362" text-anchor="middle" font-size="10" fill="#444444">__RB_APPLY_SA__</text>
  <text x="565" y="380" text-anchor="middle" font-size="10" fill="#666666">impersonated on merges to __RB_BRANCH__</text>
  <text x="565" y="396" text-anchor="middle" font-size="10" fill="#666666">creates and changes infrastructure</text>

  <line x1="195" y1="406" x2="330" y2="462" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="565" y1="406" x2="430" y2="462" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="190" y="466" width="380" height="66" rx="6" fill="#eef2f8" stroke="#3f5f8d" stroke-width="1.5"/>
  <text x="380" y="489" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GCS state bucket</text>
  <text x="380" y="507" text-anchor="middle" font-size="11" fill="#444444">gs://__RB_BUCKET__</text>
  <text x="380" y="523" text-anchor="middle" font-size="10" fill="#666666">OpenTofu / Terraform state</text>


  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/>
    </marker>
  </defs>
</svg>
SVGEOF

  sed -i.bak \
    -e "s|__RB_PROJECT_NUMBER__|$(svg_escape "$PROJECT_NUMBER")|g" \
    -e "s|__RB_PROJECT__|$(svg_escape "$PROJECT")|g" \
    -e "s|__RB_REPO__|$(svg_escape "$repo_label")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_POOL__|$(svg_escape "$POOL")|g" \
    -e "s|__RB_PROVIDER__|$(svg_escape "$PROVIDER")|g" \
    -e "s|__RB_ISSUER__|$(svg_escape "${PROVIDER_ISSUER:-https://token.actions.githubusercontent.com}")|g" \
    -e "s|__RB_PLAN_SA__|$(svg_escape "$plan_label")|g" \
    -e "s|__RB_APPLY_SA__|$(svg_escape "$apply_label")|g" \
    -e "s|__RB_BUCKET__|$(svg_escape "$RB_StateBucketName")|g" \
    "$file"
  rm -f "$file.bak"

  if grep -q '__RB_' "$file"; then
    log_warn "The diagram still has unsubstituted placeholders; wrote it anyway at ${RB_ProjectName}/pipelines-bootstrap.svg."
  else
    log_info "Wrote ${RB_ProjectName}/pipelines-bootstrap.svg (shown as an image in the Changed files panel)."
  fi
}

# Each project bootstrapped into this repository gets its own diagram and its own README, because
# every project has its own identities, state and IDs. A root-level document would be overwritten by
# the next one.
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

write_project_readme() {
  local dir="$REPO_FILES/${RB_ProjectName}" doc target title=""
  doc="$dir/README.md"
  target="$doc"

  # The same outcomes the root README uses, so nothing a human wrote is ever lost:
  #   a stub     -> replace it, keeping whatever title was there
  #   anything else, including a README this runbook wrote and someone has since edited
  #              -> leave it alone and write the generated document alongside it
  if [ -f "$doc" ]; then
    if readme_is_stub "$doc"; then
      log_warn "${RB_ProjectName}/README.md is still a stub; replacing it."
      title=$(head -1 "$doc" | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    else
      target="$dir/README.template.md"
      log_info "${RB_ProjectName}/README.md already exists and has real content; leaving it untouched."
      log_info "Writing the generated documentation to ${RB_ProjectName}/README.template.md instead."
    fi
  fi
  [ -n "$title" ] || title="${RB_ProjectName}"

  cat > "$target" <<'MDEOF'
# __RB_TITLE__

Gruntwork Pipelines is bootstrapped for this environment in GCP project `__RB_PROJECT__`.

![What the bootstrap provisioned](pipelines-bootstrap.svg)

## Identifiers

| | |
|---|---|
| GCP project | `__RB_PROJECT__` |
| Project number | `__RB_PROJECT_NUMBER__` |
| Deploy branch | `__RB_BRANCH__` |
| Workload Identity Pool | `__RB_POOL__` |
| Pool provider | `__RB_PROVIDER__` |
| Plan service account | `__RB_PLAN_SA__` |
| Apply service account | `__RB_APPLY_SA__` |
| State bucket | `gs://__RB_BUCKET__` |

## How this project is deployed

Pipelines impersonates the plan service account on pull requests and the apply service account on
merges to `__RB_BRANCH__`, for changes under `__RB_NAME__/`. The bootstrap stack that created these
resources is in `__RB_NAME__/bootstrap`.

MDEOF

  sed -i.bak \
    -e "s|__RB_NAME__|$(svg_escape "$RB_ProjectName")|g" \
    -e "s|__RB_PROJECT_NUMBER__|$(svg_escape "$PROJECT_NUMBER")|g" \
    -e "s|__RB_PROJECT__|$(svg_escape "$PROJECT")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_POOL__|$(svg_escape "$POOL")|g" \
    -e "s|__RB_PROVIDER__|$(svg_escape "$PROVIDER")|g" \
    -e "s|__RB_PLAN_SA__|$(svg_escape "${PREFIX}-plan@${PROJECT}.iam.gserviceaccount.com")|g" \
    -e "s|__RB_APPLY_SA__|$(svg_escape "${PREFIX}-apply@${PROJECT}.iam.gserviceaccount.com")|g" \
    -e "s|__RB_BUCKET__|$(svg_escape "$RB_StateBucketName")|g" \
    -e "s|__RB_TITLE__|$(svg_escape "$title")|g" \
    "$target"
  rm -f "$target.bak"

  # A failed substitution must not be reported as success: check the result, do not assume it.
  if grep -q '__RB_' "$target"; then
    log_warn "$(basename "$target") still has unsubstituted placeholders; check the values above."
  else
    log_info "Wrote ${RB_ProjectName}/$(basename "$target") documenting this project."
  fi
}

# Only draw it when every resource was read back. A diagram with blank labels would be committed
# into the pull request and would misrepresent the project, which is worse than no diagram.
if [ "$missing" -gt 0 ]; then
  log_warn "Skipping the diagram: not every resource could be read back."
elif [ -z "${REPO_FILES:-}" ]; then
  log_warn "No repository checkout available; skipping the diagram."
else
  write_diagram
  write_project_readme
fi

log_info ""
if [ "$missing" -gt 0 ]; then
  log_warn "${missing} expected resource(s) could not be read back. If the apply above succeeded,"
  log_warn "check that this account can read IAM and Cloud Storage in project ${PROJECT}."
  exit 2
fi

log_info "All bootstrap resources are present in project ${PROJECT}."
exit 0
)

set +e
show_resources
rc=$?
set -e

# rc 2 means the apply worked but something could not be read back afterwards -- a warning, not a
# failure, and the runbook's own convention for exactly that.
exit "$rc"
