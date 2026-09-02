#!/bin/bash
# Apply the bootstrap stack. Creates real Azure resources: the state Resource Group / Storage Account /
# Container, and the plan/apply Entra ID applications + service principals + role assignments. Review
# the plan output above before running this. State is local at this point; we migrate it afterwards.
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

RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_out_read_details_azure_subscription_id=$(rb_unquote "{{ .outputs.read_details.azure_subscription_id }}")
RB_out_read_details_azure_tenant_id=$(rb_unquote "{{ .outputs.read_details.azure_tenant_id }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_StateResourceGroupName=$(rb_unquote "{{ .inputs.StateResourceGroupName }}")
RB_StateStorageAccountName=$(rb_unquote "{{ .inputs.StateStorageAccountName }}")
RB_StateStorageContainerName=$(rb_unquote "{{ .inputs.StateStorageContainerName }}")
RB_out_read_details_deploy_branch=$(rb_unquote "{{ .outputs.read_details.deploy_branch }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

export ARM_TENANT_ID="${RB_out_read_details_azure_tenant_id}"
export ARM_SUBSCRIPTION_ID="${RB_out_read_details_azure_subscription_id}"

cd "$REPO_FILES/${RB_SubscriptionName}"

log_info "Applying the bootstrap stack (reusing the stack generated during plan)..."
terragrunt run --all --non-interactive --provider-cache --no-stack-generate apply

log_info "Bootstrap apply complete in subscription ${RB_out_read_details_azure_subscription_id}."

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
SUBSCRIPTION="$RB_out_read_details_azure_subscription_id"
TENANT="$RB_out_read_details_azure_tenant_id"

missing=0

# Filled in by the lookups below and used to label the diagram.
LAST_APP_ID=""
PLAN_APP_ID=""
APPLY_APP_ID=""

show_app() {
  local name=$1 label=$2 app_id object_id creds sp_id
  app_id=$(az ad app list --display-name "$name" --query "[0].appId" --output tsv 2>/dev/null)
  if [ -z "$app_id" ] || [ "$app_id" = "None" ]; then
    log_warn "${label} application ${name}: not found"
    missing=$((missing + 1))
    return
  fi
  LAST_APP_ID="$app_id"
  object_id=$(az ad app list --display-name "$name" --query "[0].id" --output tsv 2>/dev/null)
  log_info "${label} application"
  log_info "  name       ${name}"
  log_info "  client id  ${app_id}"
  log_info "  object id  ${object_id:-unknown}"

  sp_id=$(az ad sp list --display-name "$name" --query "[0].id" --output tsv 2>/dev/null)
  [ -n "$sp_id" ] && [ "$sp_id" != "None" ] && log_info "  sp obj id  ${sp_id}"

  # The federated credential is what actually lets GitHub Actions sign in as this app, so its
  # subject is the single most useful thing to see here.
  creds=$(az ad app federated-credential list --id "$app_id" \
    --query "[].{n:name,s:subject}" --output tsv 2>/dev/null)
  if [ -n "$creds" ]; then
    while IFS=$'\t' read -r cname csubject; do
      [ -n "$cname" ] && log_info "  fed cred   ${cname}  subject=${csubject}"
    done <<< "$creds"
  else
    log_warn "  no federated credentials on ${name}"
    missing=$((missing + 1))
  fi
}

show_role_definition() {
  local name=$1 label=$2 role_id
  role_id=$(az role definition list --name "$name" --scope "/subscriptions/${SUBSCRIPTION}" \
    --query "[0].id" --output tsv 2>/dev/null)
  if [ -z "$role_id" ] || [ "$role_id" = "None" ]; then
    log_warn "${label} custom role ${name}: not found"
    missing=$((missing + 1))
    return
  fi
  log_info "${label} custom role"
  log_info "  name       ${name}"
  log_info "  id         ${role_id}"
}

show_state_storage() {
  local rg_location sa_json sa_location sa_kind https_only container
  rg_location=$(az group show --name "$RB_StateResourceGroupName" --query location --output tsv 2>/dev/null)
  if [ -z "$rg_location" ]; then
    log_warn "State resource group ${RB_StateResourceGroupName}: not found"
    missing=$((missing + 1))
  else
    log_info "State resource group"
    log_info "  name       ${RB_StateResourceGroupName}"
    log_info "  location   ${rg_location}"
  fi

  log_info ""
  sa_json=$(az storage account show --name "$RB_StateStorageAccountName" \
    --resource-group "$RB_StateResourceGroupName" --output json 2>/dev/null)
  if [ -z "$sa_json" ]; then
    log_warn "State storage account ${RB_StateStorageAccountName}: not found"
    missing=$((missing + 1))
    return
  fi
  sa_location=$(printf '%s' "$sa_json" | jq -r '.location // "unknown"' 2>/dev/null)
  sa_kind=$(printf '%s' "$sa_json" | jq -r '.kind // "unknown"' 2>/dev/null)
  https_only=$(printf '%s' "$sa_json" | jq -r 'if .enableHttpsTrafficOnly then "yes" else "no" end' 2>/dev/null)
  log_info "State storage account"
  log_info "  name       ${RB_StateStorageAccountName}"
  log_info "  location   ${sa_location}"
  log_info "  kind       ${sa_kind}"
  log_info "  https only ${https_only}"

  container=$(az storage container exists --name "$RB_StateStorageContainerName" \
    --account-name "$RB_StateStorageAccountName" --auth-mode login \
    --query exists --output tsv 2>/dev/null)
  if [ "$container" = "true" ]; then
    log_info "  container  ${RB_StateStorageContainerName}"
  else
    log_warn "State container ${RB_StateStorageContainerName}: not found (or not readable with these credentials)"
    missing=$((missing + 1))
  fi
}

log_info "Reading back what the bootstrap created in subscription ${SUBSCRIPTION}"
log_info "(tenant ${TENANT})..."
log_info ""
LAST_APP_ID=""
show_app "${PREFIX}-plan" "Plan"
PLAN_APP_ID="$LAST_APP_ID"
log_info ""
LAST_APP_ID=""
show_app "${PREFIX}-apply" "Apply"
APPLY_APP_ID="$LAST_APP_ID"
log_info ""
show_role_definition "${PREFIX}-plan-custom-role" "Plan"
log_info ""
show_role_definition "${PREFIX}-apply-custom-role" "Apply"
log_info ""
show_state_storage
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
  local dir="$REPO_FILES/${RB_SubscriptionName}" file="$REPO_FILES/${RB_SubscriptionName}/pipelines-bootstrap.svg"
  mkdir -p "$dir" || { log_warn "Could not create ${dir}; skipping the diagram."; return 0; }

  local repo_label
  repo_label=$(clip "${RB_out_clone_repo_owner}/${RB_out_clone_repo_name}" 78)

  cat > "$file" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="580" viewBox="0 0 760 580" font-family="Helvetica, Arial, sans-serif">
  <rect width="760" height="580" fill="#ffffff"/>
  <text x="380" y="34" text-anchor="middle" font-size="17" font-weight="bold" fill="#1a1a1a">Gruntwork Pipelines bootstrap</text>
  <text x="380" y="54" text-anchor="middle" font-size="12" fill="#666666">Azure subscription __RB_SUBSCRIPTION__</text>

  <rect x="130" y="80" width="500" height="62" rx="6" fill="#f4f6f8" stroke="#5b6b7c" stroke-width="1.5"/>
  <text x="380" y="103" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GitHub Actions</text>
  <text x="380" y="121" text-anchor="middle" font-size="11" fill="#444444">__RB_REPO__</text>
  <text x="380" y="136" text-anchor="middle" font-size="11" fill="#444444">deploy branch: __RB_BRANCH__</text>

  <line x1="380" y1="142" x2="380" y2="182" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="392" y="167" font-size="10" fill="#666666">OIDC token</text>

  <rect x="150" y="182" width="460" height="66" rx="6" fill="#fdf3e3" stroke="#c98a1b" stroke-width="1.5"/>
  <text x="380" y="205" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Entra ID federated credentials</text>
  <text x="380" y="223" text-anchor="middle" font-size="11" fill="#444444">tenant __RB_TENANT__</text>
  <text x="380" y="239" text-anchor="middle" font-size="10" fill="#666666">trusts only this repository and branch</text>

  <line x1="300" y1="248" x2="190" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="460" y1="248" x2="570" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="20" y="304" width="350" height="102" rx="6" fill="#eef5ee" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan application</text>
  <text x="195" y="346" text-anchor="middle" font-size="10" fill="#444444">__RB_PLAN_APP__</text>
  <text x="195" y="363" text-anchor="middle" font-size="10" fill="#444444">role: __RB_PLAN_ROLE__</text>
  <text x="195" y="381" text-anchor="middle" font-size="10" fill="#666666">signs in on pull requests</text>
  <text x="195" y="397" text-anchor="middle" font-size="10" fill="#666666">read only</text>

  <rect x="390" y="304" width="350" height="102" rx="6" fill="#fdeeee" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply application</text>
  <text x="565" y="346" text-anchor="middle" font-size="10" fill="#444444">__RB_APPLY_APP__</text>
  <text x="565" y="363" text-anchor="middle" font-size="10" fill="#444444">role: __RB_APPLY_ROLE__</text>
  <text x="565" y="381" text-anchor="middle" font-size="10" fill="#666666">signs in on merges to __RB_BRANCH__</text>
  <text x="565" y="397" text-anchor="middle" font-size="10" fill="#666666">creates and changes infrastructure</text>

  <line x1="195" y1="406" x2="330" y2="470" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="565" y1="406" x2="430" y2="470" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="170" y="474" width="420" height="82" rx="6" fill="#eef2f8" stroke="#3f5f8d" stroke-width="1.5"/>
  <text x="380" y="497" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">State storage</text>
  <text x="380" y="515" text-anchor="middle" font-size="11" fill="#444444">__RB_STORAGE__ / __RB_CONTAINER__</text>
  <text x="380" y="531" text-anchor="middle" font-size="10" fill="#666666">resource group: __RB_RG__</text>
  <text x="380" y="547" text-anchor="middle" font-size="10" fill="#666666">OpenTofu / Terraform state</text>


  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/>
    </marker>
  </defs>
</svg>
SVGEOF

  sed -i.bak \
    -e "s|__RB_SUBSCRIPTION__|$(svg_escape "$SUBSCRIPTION")|g" \
    -e "s|__RB_TENANT__|$(svg_escape "$TENANT")|g" \
    -e "s|__RB_REPO__|$(svg_escape "$repo_label")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_PLAN_APP__|$(svg_escape "${PLAN_APP_ID:-unknown}")|g" \
    -e "s|__RB_APPLY_APP__|$(svg_escape "${APPLY_APP_ID:-unknown}")|g" \
    -e "s|__RB_PLAN_ROLE__|$(svg_escape "${PREFIX}-plan-custom-role")|g" \
    -e "s|__RB_APPLY_ROLE__|$(svg_escape "${PREFIX}-apply-custom-role")|g" \
    -e "s|__RB_STORAGE__|$(svg_escape "$RB_StateStorageAccountName")|g" \
    -e "s|__RB_CONTAINER__|$(svg_escape "$RB_StateStorageContainerName")|g" \
    -e "s|__RB_RG__|$(svg_escape "$RB_StateResourceGroupName")|g" \
    "$file"
  rm -f "$file.bak"

  if grep -q '__RB_' "$file"; then
    log_warn "The diagram still has unsubstituted placeholders; wrote it anyway at ${RB_SubscriptionName}/pipelines-bootstrap.svg."
  else
    log_info "Wrote ${RB_SubscriptionName}/pipelines-bootstrap.svg (shown as an image in the Changed files panel)."
  fi
}

# Each subscription bootstrapped into this repository gets its own diagram and its own README, because
# every subscription has its own identities, state and IDs. A root-level document would be overwritten by
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

write_subscription_readme() {
  local dir="$REPO_FILES/${RB_SubscriptionName}" doc target title=""
  doc="$dir/README.md"
  target="$doc"

  # The same outcomes the root README uses, so nothing a human wrote is ever lost:
  #   a stub     -> replace it, keeping whatever title was there
  #   anything else, including a README this runbook wrote and someone has since edited
  #              -> leave it alone and write the generated document alongside it
  if [ -f "$doc" ]; then
    if readme_is_stub "$doc"; then
      log_warn "${RB_SubscriptionName}/README.md is still a stub; replacing it."
      title=$(head -1 "$doc" | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    else
      target="$dir/README.template.md"
      log_info "${RB_SubscriptionName}/README.md already exists and has real content; leaving it untouched."
      log_info "Writing the generated documentation to ${RB_SubscriptionName}/README.template.md instead."
    fi
  fi
  [ -n "$title" ] || title="${RB_SubscriptionName}"

  cat > "$target" <<'MDEOF'
# __RB_TITLE__

Gruntwork Pipelines is bootstrapped for this environment in Azure subscription `__RB_SUBSCRIPTION__`.

![What the bootstrap provisioned](pipelines-bootstrap.svg)

## Identifiers

| | |
|---|---|
| Subscription | `__RB_SUBSCRIPTION__` |
| Tenant | `__RB_TENANT__` |
| Deploy branch | `__RB_BRANCH__` |
| Plan application | `__RB_PLAN_APP__` |
| Apply application | `__RB_APPLY_APP__` |
| Plan role | `__RB_PLAN_ROLE__` |
| Apply role | `__RB_APPLY_ROLE__` |
| State storage | `__RB_STORAGE__` / `__RB_CONTAINER__` |
| State resource group | `__RB_RG__` |

## How this subscription is deployed

Pipelines signs in as the plan application on pull requests and as the apply application on merges to
`__RB_BRANCH__`, for changes under `__RB_NAME__/`. The bootstrap stack that created these resources
is in `__RB_NAME__/bootstrap`.

MDEOF

  sed -i.bak \
    -e "s|__RB_NAME__|$(svg_escape "$RB_SubscriptionName")|g" \
    -e "s|__RB_SUBSCRIPTION__|$(svg_escape "$SUBSCRIPTION")|g" \
    -e "s|__RB_TENANT__|$(svg_escape "$TENANT")|g" \
    -e "s|__RB_BRANCH__|$(svg_escape "$RB_out_read_details_deploy_branch")|g" \
    -e "s|__RB_PLAN_APP__|$(svg_escape "${PLAN_APP_ID:-unknown}")|g" \
    -e "s|__RB_APPLY_APP__|$(svg_escape "${APPLY_APP_ID:-unknown}")|g" \
    -e "s|__RB_PLAN_ROLE__|$(svg_escape "${PREFIX}-plan-custom-role")|g" \
    -e "s|__RB_APPLY_ROLE__|$(svg_escape "${PREFIX}-apply-custom-role")|g" \
    -e "s|__RB_STORAGE__|$(svg_escape "$RB_StateStorageAccountName")|g" \
    -e "s|__RB_CONTAINER__|$(svg_escape "$RB_StateStorageContainerName")|g" \
    -e "s|__RB_RG__|$(svg_escape "$RB_StateResourceGroupName")|g" \
    -e "s|__RB_TITLE__|$(svg_escape "$title")|g" \
    "$target"
  rm -f "$target.bak"

  # A failed substitution must not be reported as success: check the result, do not assume it.
  if grep -q '__RB_' "$target"; then
    log_warn "$(basename "$target") still has unsubstituted placeholders; check the values above."
  else
    log_info "Wrote ${RB_SubscriptionName}/$(basename "$target") documenting this subscription."
  fi
}

# Only draw it when every resource was read back. A diagram with blank labels would be committed
# into the pull request and would misrepresent the subscription, which is worse than no diagram.
if [ "$missing" -gt 0 ]; then
  log_warn "Skipping the diagram: not every resource could be read back."
elif [ -z "${REPO_FILES:-}" ]; then
  log_warn "No repository checkout available; skipping the diagram."
else
  write_diagram
  write_subscription_readme
fi

log_info ""
if [ "$missing" -gt 0 ]; then
  log_warn "${missing} expected resource(s) could not be read back. If the apply above succeeded,"
  log_warn "check that this identity can read Entra ID and the subscription's resources."
  exit 2
fi

log_info "All bootstrap resources are present in subscription ${SUBSCRIPTION}."
exit 0
)

set +e
show_resources
rc=$?
set -e

# rc 2 means the apply worked but something could not be read back afterwards -- a warning, not a
# failure, and the runbook's own convention for exactly that.
exit "$rc"
