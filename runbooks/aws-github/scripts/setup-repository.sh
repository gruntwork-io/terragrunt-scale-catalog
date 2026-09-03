#!/bin/bash
# Set up the repository in one pass: render the Terragrunt Scale configuration, install the tool
# versions it pins, add the Pipelines CI workflows, and write the README.
#
# These were four separate blocks. They are one script because each depends on the one before it and
# there is no useful place to stop in between — and because the Runbooks app renders template
# variables only into the script a block points at, so a wrapper cannot call the four in turn.
#
# Each phase runs in a subshell, so its own `cd`, `set` and `exit` stay local to it. A phase that
# fails stops the run and names itself, and the phases before it have already done their work: fix
# the problem and run the step again.
set -euo pipefail

# Banner, folded in from logo.sh. Printed to stdout rather than stderr: nothing here is an error,
# and when a block runs without a PTY the app reads stdout and stderr as two separate streams, so a
# stderr banner can land after the first few log lines instead of at the top.
logo() {
  # 256-colour purple (xterm 93, #8700ff) rather than the basic 16-colour palette, whose only purple
  # is magenta. Rendered by the app through ansi-to-react, and by any 256-colour terminal in
  # instruction mode.
  printf "\033[38;5;93m"
  cat <<'LOGOEOF'

████████╗███████╗██████╗ ██████╗  █████╗  ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║   ██║████╗  ██║╚══██╔══╝
   ██║   █████╗  ██████╔╝██████╔╝███████║██║  ███╗██████╔╝██║   ██║██╔██╗ ██║   ██║
   ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║
   ██║   ███████╗██║  ██║██║  ██║██║  ██║╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║   ██║
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝
                                                                           ▄▄▄
                    ███████╗ ██████╗ █████╗ ██╗     ███████╗             ▄▀░░░▀▄
                    ██╔════╝██╔════╝██╔══██╗██║     ██╔════╝           ▄▀░░░░░░░▀▄
                    ███████╗██║     ███████║██║     █████╗           ▄▀░░░░░░░░░░░▀▄
                    ╚════██║██║     ██╔══██║██║     ██╔══╝           █▀▄░░░░░░░░░▄▀█
                    ███████║╚██████╗██║  ██║███████╗███████╗         █▓▓▀▄░░░░░▄▀▒▒█
                    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝         █▓▓▓▓▀▄▄▄▀▒▒▒▒█
By Gruntwork                                                          ▀▄▓▓▓▓█▒▒▒▒▄▀
                                                                        ▀▄▓▓█▒▒▄▀
                                                                          ▀▄█▄▀


LOGOEOF
  printf "\033[0m"
}

logo


# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and one pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_AWSRegion=$(rb_unquote "{{ .inputs.AWSRegion }}")
RB_AccountName=$(rb_unquote "{{ .inputs.AccountName }}")
RB_DeployBranch=$(rb_unquote "{{ .outputs.read_details.deploy_branch }}")
RB_IaCTool=$(rb_unquote "{{ .inputs.IaCTool }}")
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
RB_Issuer=$(rb_unquote "{{ .inputs.Issuer }}")
if [ "$RB_Issuer" = "default" ]; then RB_Issuer=""; fi
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_TerraformVersion=$(rb_unquote "{{ .inputs.TerraformVersion }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")
RB_out_clone_org_id=$(rb_unquote "{{ .outputs.clone.org_id }}")
RB_out_clone_repo_id=$(rb_unquote "{{ .outputs.clone.repo_id }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")
RB_out_read_details_aws_account_id=$(rb_unquote "{{ .outputs.read_details.aws_account_id }}")
RB_out_read_details_partition=$(rb_unquote "{{ .outputs.read_details.partition }}")
RB_out_read_details_repo_mode=$(rb_unquote "{{ .outputs.read_details.repo_mode }}")
RB_out_plan_imports_additional_audiences=$(rb_unquote "{{ .outputs.plan_imports.additional_audiences }}")
RB_out_plan_imports_apply_attachment_import=$(rb_unquote "{{ .outputs.plan_imports.apply_attachment_import }}")
RB_out_plan_imports_apply_role_name=$(rb_unquote "{{ .outputs.plan_imports.apply_role_name }}")
RB_out_plan_imports_plan_role_name=$(rb_unquote "{{ .outputs.plan_imports.plan_role_name }}")
RB_out_plan_imports_apply_policy_import=$(rb_unquote "{{ .outputs.plan_imports.apply_policy_import }}")
RB_out_plan_imports_apply_role_import=$(rb_unquote "{{ .outputs.plan_imports.apply_role_import }}")
RB_out_plan_imports_exclude_oidc_provider=$(rb_unquote "{{ .outputs.plan_imports.exclude_oidc_provider }}")
RB_out_plan_imports_oidc_import_existing=$(rb_unquote "{{ .outputs.plan_imports.oidc_import_existing }}")
RB_out_plan_imports_oidc_provider_tags=$(rb_unquote "{{ .outputs.plan_imports.oidc_provider_tags }}")
RB_out_plan_imports_plan_attachment_import=$(rb_unquote "{{ .outputs.plan_imports.plan_attachment_import }}")
RB_out_plan_imports_plan_policy_import=$(rb_unquote "{{ .outputs.plan_imports.plan_policy_import }}")
RB_out_plan_imports_plan_role_import=$(rb_unquote "{{ .outputs.plan_imports.plan_role_import }}")
RB_out_resolve_versions_catalog_ref=$(rb_unquote "{{ .outputs.resolve_versions.catalog_ref }}")
RB_out_resolve_versions_opentofu_version=$(rb_unquote "{{ .outputs.resolve_versions.opentofu_version }}")
RB_out_resolve_versions_terraform_version=$(rb_unquote "{{ .outputs.resolve_versions.terraform_version }}")
RB_out_resolve_versions_terragrunt_version=$(rb_unquote "{{ .outputs.resolve_versions.terragrunt_version }}")
RB_OverwriteWorkflows=$(rb_unquote "{{ .inputs.OverwriteWorkflows }}")
RB_repo_mode="${RB_out_read_details_repo_mode}"

MODE="${RB_out_read_details_repo_mode}"

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone step first."
  exit 1
fi

cd "$REPO_FILES"

case "$MODE" in
  scaffold) TEMPLATE="infrastructure-live" ;;
  account)  TEMPLATE="account" ;;
  *) log_error "Unknown repository mode [${MODE}]. Re-run the repository check in step 3."; exit 1 ;;
esac

# Everything this bootstrap pins is decided the same way, in order of authority:
#   1. an explicit override typed (or selected) in the form;
#   2. the newest release discovered by the resolve step;
#   3. a known-good built-in pin, so an offline run still produces a working repository.
# "latest" is each field's default: a non-empty sentinel, because a blank optional input leaves the
# whole block waiting on an unmet dependency and it can never be run.
# The result comes back in $PICKED rather than on stdout: the runbook log helpers write to stdout,
# so capturing this function with $(...) would fold its own log line into the value it returns.
PICKED=""
pick_version() {
  label=$1; from_form=$2; resolved=$3; fallback=$4
  if [ -n "$from_form" ] && [ "$from_form" != "latest" ]; then
    PICKED="$from_form"
    log_info "${label}: ${PICKED} (pinned in the form)"
  elif [ -n "$resolved" ]; then
    PICKED="$resolved"
    log_info "${label}: ${PICKED} (newest release)"
  else
    PICKED="$fallback"
    log_warn "${label}: ${PICKED} (could not resolve the newest release; using the built-in pin)"
  fi
}

pick_version "terragrunt-scale-catalog" \
  "$RB_TerragruntScaleCatalogRef" "$RB_out_resolve_versions_catalog_ref" "v1.13.1"
CATALOG_REF="$PICKED"

pick_version "Terragrunt" \
  "$RB_TerragruntVersion" "$RB_out_resolve_versions_terragrunt_version" "1.0.0"
TERRAGRUNT_VERSION="$PICKED"

pick_version "OpenTofu" \
  "$RB_OpenTofuVersion" "$RB_out_resolve_versions_opentofu_version" "1.11.5"
OPENTOFU_VERSION="$PICKED"

pick_version "Terraform" \
  "$RB_TerraformVersion" "$RB_out_resolve_versions_terraform_version" "1.15.9"
TERRAFORM_VERSION="$PICKED"

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

# --- Render the Terragrunt Scale configuration -------------------
phase_generate() (
# The variable file is written OUTSIDE the repository. It used to be created at the repo root and
# deleted after a successful render, which meant a failed render left it behind — and the pull
# request step stages with `git add -A`, so the leftover would be committed. A temp file cannot be
# committed, and the trap removes it whichever way this phase exits.
VARS_FILE="$(mktemp -d)/vars.yml"
trap 'rm -rf "$(dirname "$VARS_FILE")"' EXIT

# Clear out a vars.yml left in the repo by an older run of this runbook. Matched on the key only
# this template writes, so a file of the user's own with that name is never touched.
if [ -f vars.yml ] && grep -q '^TerragruntScaleCatalogRef:' vars.yml; then
  rm -f vars.yml

# Boilerplate ignores variables a template does not declare, so a catalog ref from before role
# naming existed would quietly render prefix-named roles instead. Check the result rather than
# assume it: the wrong roles here mean Pipelines assumes an ARN that was never created.
if [ -n "${RB_out_plan_imports_plan_role_name}${RB_out_plan_imports_apply_role_name}" ]; then
  env_hcl=".gruntwork/environment-${RB_AccountName}.hcl"
  if [ -f "$env_hcl" ] && ! grep -q "role/${RB_out_plan_imports_plan_role_name:-$RB_OIDCResourcePrefix-plan}\"" "$env_hcl"; then
    log_error "A custom IAM role name was requested, but catalog ref ${CATALOG_REF} rendered the"
    log_error "default prefix-based names instead: it predates PlanIAMRoleName/ApplyIAMRoleName."
    log_error "Pin a catalog release that supports them, or set both names back to default."
    exit 1
  fi
  log_info "Rendered with the requested IAM role names."
fi

  log_info "Removed a vars.yml left in the repository by an earlier run."
fi

log_info "Writing vars.yml for the aws/github/${TEMPLATE} template..."
cat > "$VARS_FILE" <<EOF
AccountName: "${RB_AccountName}"
AWSAccountID: "${RB_out_read_details_aws_account_id}"
AWSRegion: "${RB_AWSRegion}"
StateBucketName: "${RB_StateBucketName}"
Partition: "${RB_out_read_details_partition}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
GitHubOrgName: "${RB_out_clone_repo_owner}"
GitHubRepoName: "${RB_out_clone_repo_name}"
GitHubOrgID: "${RB_out_clone_org_id}"
GitHubRepoID: "${RB_out_clone_repo_id}"
DeployBranch: "${RB_DeployBranch}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
OIDCProviderImportExisting: ${RB_out_plan_imports_oidc_import_existing:-false}
ExcludeOIDCProvider: ${RB_out_plan_imports_exclude_oidc_provider:-false}
PlanIAMRoleImportExisting: ${RB_out_plan_imports_plan_role_import:-false}
PlanIamPolicyImportExisting: ${RB_out_plan_imports_plan_policy_import:-false}
PlanIAMRolePolicyAttachmentImportExisting: ${RB_out_plan_imports_plan_attachment_import:-false}
ApplyIAMRoleImportExisting: ${RB_out_plan_imports_apply_role_import:-false}
ApplyIamPolicyImportExisting: ${RB_out_plan_imports_apply_policy_import:-false}
ApplyIAMRolePolicyAttachmentImportExisting: ${RB_out_plan_imports_apply_attachment_import:-false}
EOF

# Audiences and tags are only written when there is something to carry across: the template treats
# an empty list or map as "not set" either way, and leaving them out keeps vars.yml readable.
# A custom issuer has to reach the template too: it builds the OIDC provider's ARN from it.
[ -n "$RB_Issuer" ] && echo "Issuer: \"${RB_Issuer}\"" >> "$VARS_FILE"
[ -n "${RB_out_plan_imports_plan_role_name}" ] && echo "PlanIAMRoleName: \"${RB_out_plan_imports_plan_role_name}\"" >> "$VARS_FILE"
[ -n "${RB_out_plan_imports_apply_role_name}" ] && echo "ApplyIAMRoleName: \"${RB_out_plan_imports_apply_role_name}\"" >> "$VARS_FILE"
if [ -n "${RB_out_plan_imports_additional_audiences}" ] && [ "${RB_out_plan_imports_additional_audiences}" != "[]" ]; then
  echo "AdditionalAudiences: ${RB_out_plan_imports_additional_audiences}" >> "$VARS_FILE"
fi
if [ -n "${RB_out_plan_imports_oidc_provider_tags}" ] && [ "${RB_out_plan_imports_oidc_provider_tags}" != "{}" ]; then
  echo "OIDCProviderTags: ${RB_out_plan_imports_oidc_provider_tags}" >> "$VARS_FILE"
fi

# Only the full-repository template renders .mise.toml and the CI workflows, so only it takes
# the tool versions and the drift-detection switch.
if [ "$MODE" = "scaffold" ]; then
  cat >> "$VARS_FILE" <<EOF
IncludeDriftDetection: ${RB_IncludeDriftDetection}
TerragruntVersion: "${TERRAGRUNT_VERSION}"
OpenTofuVersion: "${OPENTOFU_VERSION}"
IaCTool: "${RB_IaCTool}"
TerraformVersion: "${TERRAFORM_VERSION}"
EOF
fi

log_info "Rendering aws/github/${TEMPLATE} template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/github/${TEMPLATE}?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file "$VARS_FILE" \
  --non-interactive


# Catalog releases from the version that added IaCTool onwards render the right pin and tf_binary
# themselves, and the reconciliation below then finds nothing to do. Older refs — including any
# already-published ref a user may pin — do not, so the rendered files are reconciled here. Both must agree: tf_binary tells Pipelines which binary to run
# (it exports TG_TF_PATH), and .mise.toml decides which binary is actually installed — locally and in
# CI, which runs `mise install` against this repo. Setting one without the other breaks the run.
apply_iac_tool_choice() {
  hcl=".gruntwork/repository.hcl"

  # Which binary actually governs this repository, in order of authority:
  #   1. a tf_binary already committed here — Pipelines reads it, and switching it on live
  #      infrastructure needs a state migration, so the runbook never flips it;
  #   2. the tool the repository's own .mise.toml already pins;
  #   3. only if neither exists, the choice made in the form.
  # An existing repository therefore keeps what it has, whatever the form happens to default to.
  effective=""
  source_of_truth=""
  if [ -f "$hcl" ] && grep -q 'tf_binary' "$hcl"; then
    existing=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$hcl" | head -1)
    if [ -n "$existing" ]; then
      effective="$existing"; source_of_truth="repository.hcl"
      log_info "repository.hcl already sets tf_binary = \"${existing}\"; leaving it unchanged."
    fi
  fi
  if [ -z "$effective" ] && [ -f .mise.toml ]; then
    if grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml; then
      effective="terraform"; source_of_truth=".mise.toml"
    elif grep -qE '^[[:space:]]*"?opentofu"?[[:space:]]*=' .mise.toml; then
      effective="opentofu"; source_of_truth=".mise.toml"
    fi
    [ -n "$effective" ] && log_info "This repository's .mise.toml already pins ${effective}; keeping it."
  fi
  if [ -z "$effective" ]; then
    effective="$RB_IaCTool"; source_of_truth="the form"
  fi

  if [ "$effective" != "$RB_IaCTool" ]; then
    log_warn "You chose ${RB_IaCTool}, but this repository already uses ${effective} (per ${source_of_truth})."
    log_warn "Keeping ${effective}. Switching an existing repository between OpenTofu and Terraform"
    log_warn "requires a state migration and is deliberately out of scope for this runbook."
  fi

  # Record the choice where Pipelines reads it, but only when it is not already recorded.
  if [ -f "$hcl" ] && ! grep -q 'tf_binary' "$hcl"; then
    awk -v tool="$effective" '
      { print }
      /^repository \{/ && !done {
        print "  // The IaC binary Pipelines instructs Terragrunt to use: \"opentofu\" (recommended) or \"terraform\"."
        print "  // Docs: https://docs.gruntwork.io/2.0/reference/pipelines/configurations-as-code/api#tf_binary"
        print "  tf_binary = \"" tool "\""
        print ""
        done = 1
      }
    ' "$hcl" > "$hcl.tmp" && mv "$hcl.tmp" "$hcl"
    log_info "Recorded tf_binary = \"${effective}\" in repository.hcl."
  fi

  # Align the mise pin ONLY in the file this run rendered. An existing repository's .mise.toml is
  # never edited: its tool and versions are the repository's to own, not this runbook's.
  if [ "$MODE" = "scaffold" ] && [ -f .mise.toml ]; then
    if [ "$effective" = "terraform" ] && grep -qE '^[[:space:]]*"?opentofu"?[[:space:]]*=' .mise.toml; then
      sed -i.bak -E 's|^([[:space:]]*)"?opentofu"?[[:space:]]*=.*|\1terraform = "'"${TERRAFORM_VERSION}"'"|' .mise.toml && rm -f .mise.toml.bak
      grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml \
        && log_info "Pinned terraform ${TERRAFORM_VERSION} in the rendered .mise.toml." \
        || log_warn "Tried to pin terraform in .mise.toml but the file still does not declare it."
    elif [ "$effective" = "opentofu" ] && grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml; then
      sed -i.bak -E 's|^([[:space:]]*)"?terraform"?[[:space:]]*=.*|\1opentofu = "'"${OPENTOFU_VERSION}"'"|' .mise.toml && rm -f .mise.toml.bak
      grep -qE '^[[:space:]]*"?opentofu"?[[:space:]]*=' .mise.toml \
        && log_info "Pinned opentofu ${OPENTOFU_VERSION} in the rendered .mise.toml." \
        || log_warn "Tried to pin opentofu in .mise.toml but the file still does not declare it."
    fi
  fi

  assert_iac_tool_consistent "$effective"
}

# tf_binary and the mise pin must agree: tf_binary decides what Pipelines runs (via TG_TF_PATH) and
# .mise.toml decides what gets installed, locally and in CI. Disagreement fails in CI with a missing
# binary, long after this runbook finished, so it is caught here instead. Rewrites above are matched
# against the rendered file's exact shape, and a catalog template reformat would make them silently
# no-op — this is what turns that into a loud, local failure.
assert_iac_tool_consistent() {
  want=$1
  [ -f .mise.toml ] || { log_info "No .mise.toml yet; the install step pins ${want} from your inputs."; return 0; }

  if grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml; then pinned="terraform"
  elif grep -qE '^[[:space:]]*"?opentofu"?[[:space:]]*=' .mise.toml; then pinned="opentofu"
  else
    log_warn "Could not identify an IaC binary pin in .mise.toml; skipping the consistency check."
    return 0
  fi

  if [ "$pinned" = "$want" ]; then
    log_info "IaC tool is consistent: tf_binary and .mise.toml both use ${want}."
    return 0
  fi

  log_error "Inconsistent IaC tool configuration in the generated repository:"
  log_error "  .gruntwork/repository.hcl -> tf_binary = \"${want}\"  (what Pipelines will run)"
  log_error "  .mise.toml                -> ${pinned}                 (what gets installed)"
  log_error "CI would install ${pinned} and then try to run ${want}. Fix .mise.toml to pin ${want},"
  log_error "or set tf_binary to ${pinned}, before committing this branch."
  exit 1
}

if [ "$MODE" = "scaffold" ]; then
  apply_iac_tool_choice
  log_info "Scaffolded the repository for account ${RB_AccountName}."
  exit 0
fi

# From here on: adding an account to a repository that already had root.hcl.

# Existing repos may not already ignore Terragrunt's local caches; make sure we never commit them.
touch .gitignore
grep -qxF '.terragrunt-cache' .gitignore || echo '.terragrunt-cache' >> .gitignore
grep -qxF '.terragrunt-stack' .gitignore || echo '.terragrunt-stack' >> .gitignore

log_info "Generated ${RB_AccountName}/_global/bootstrap/ and .gruntwork/environment-${RB_AccountName}.hcl"

# The account template does NOT create .gruntwork/repository.hcl (only infrastructure-live does), so
# an existing repo adopting Pipelines needs it here. Written only if absent, so bootstrapping another
# account into a repo that already has Pipelines will not clobber its repository.hcl.
REPO_HCL="$REPO_FILES/.gruntwork/repository.hcl"
if [ -f "$REPO_HCL" ]; then
  log_info ".gruntwork/repository.hcl already exists; leaving it unchanged."
else
  mkdir -p "$REPO_FILES/.gruntwork"
  cat > "$REPO_HCL" <<'REPOEOF'
// Gruntwork Pipelines repository-wide configuration.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

repository {
  // Commits on this branch trigger `terragrunt apply`. PRs against it trigger `terragrunt plan`.
  // If you change this, also update the branch trigger in your CI workflow file.
  deploy_branch_name = "__RB_DeployBranch__"

  // Controls whether each push creates a new status comment or updates the existing one in-place.
  status_update {
    new_comment_per_push = false
  }

  env {
    PIPELINES_FEATURE_EXPERIMENT_IGNORE_UNITS_WITHOUT_ENVIRONMENT = "true"
  }
}
REPOEOF
  sed -i.bak "s|__RB_DeployBranch__|${RB_DeployBranch}|g" "$REPO_HCL"
  rm -f "$REPO_HCL.bak"
  log_info "Wrote .gruntwork/repository.hcl (deploy branch: ${RB_DeployBranch})"
fi

apply_iac_tool_choice

# Publish the versions this run settled on. Nothing downstream needs them any more — the install
# phase below reads the same variables directly — but they are the record of what was pinned.
{
  echo "catalog_ref=${CATALOG_REF}"
  echo "terragrunt_version=${TERRAGRUNT_VERSION}"
  echo "opentofu_version=${OPENTOFU_VERSION}"
  echo "terraform_version=${TERRAFORM_VERSION}"
} >> "$RUNBOOK_OUTPUT"

exit 0
)

# --- Install the pinned tool dependencies ------------------------
phase_install_deps() (
# The versions come from the generate step, not straight from the form: that is where the form
# override, the newest resolved release and the built-in pin are reconciled. Reading its result back
# keeps what gets installed here identical to what was rendered into the repository.

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

cd "$REPO_FILES"

if [ ! -f .mise.toml ] && [ ! -f mise.toml ] && [ ! -f .config/mise/config.toml ]; then
  # No mise config in the repo (an existing repo not scaffolded from this catalog). Create one
  # matching what the catalog's infrastructure-live template generates for AWS. The AWS CLI is a
  # pre-flight prerequisite and is not pinned via mise.
  #
  # Which IaC binary to pin follows the same authority as the generate step: a tf_binary already
  # committed to this repository wins over the form, because that is what Pipelines will run.
  # Without this, an existing repo carrying tf_binary = "terraform" but no mise config would be
  # pinned to OpenTofu here, and CI would install one binary and then run the other.
  TOOL="$RB_IaCTool"
  if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
    recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
    if [ -n "$recorded" ] && [ "$recorded" != "$TOOL" ]; then
      log_warn "This repository records tf_binary = \"${recorded}\"; pinning ${recorded} rather than ${TOOL}."
      TOOL="$recorded"
    fi
  fi

  if [ "$TOOL" = "terraform" ]; then
    log_warn "No mise config found in the repository; pinning Terragrunt and Terraform."
    mise use "terragrunt@${TERRAGRUNT_VERSION}" "terraform@${TERRAFORM_VERSION}"
  else
    log_warn "No mise config found in the repository; pinning Terragrunt and OpenTofu."
    mise use "terragrunt@${TERRAGRUNT_VERSION}" "opentofu@${OPENTOFU_VERSION}"
  fi
fi

# Trust before installing, not after. By this point a config always exists — the repository's own,
# or the one written just above — and `mise install` is the first thing to read it. A config that is
# more than plain [tools] pins (env, templated tool options) is skipped or errors while untrusted,
# so trusting afterwards would sit downstream of the very failure it prevents.
log_info "Trusting the repository's mise config..."
mise trust --all || log_warn "Could not trust the mise config; mise may prompt the first time you run it here."

log_info "Installing the tool versions declared in the repository's mise config..."
mise install

log_info "Tool dependencies installed."
)

# --- Add the Pipelines CI workflows ------------------------------
phase_add_ci_workflows() (
if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the clone and generate steps first."
  exit 1
fi

if [ "$RB_repo_mode" = "scaffold" ]; then
  log_info "The repository scaffold already rendered the Pipelines workflows; nothing to add."
  exit 0
fi

OVERWRITE="${RB_OverwriteWorkflows}"
WF_DIR="$REPO_FILES/.github/workflows"
mkdir -p "$WF_DIR"

# Returns 0 (write) when the file is absent, or when OverwriteWorkflows is true; returns 1 (skip) when the
# file already exists and overwrite was not requested.
should_write() {
  local dest="$WF_DIR/$1"
  if [ -f "$dest" ] && [ "$OVERWRITE" != "true" ]; then
    log_warn "Skipping $1: it already exists (set OverwriteWorkflows=true to replace it)."
    return 1
  fi
  return 0
}

if should_write pipelines.yml; then
  cat > "$WF_DIR/pipelines.yml" <<'WORKFLOWEOF'
name: Pipelines
run-name: "[GWP]: ${{ "{{" }} github.event.commits[0].message || github.event.pull_request.title || 'No commit message' {{ "}}" }}"
on:
  push:
    branches:
      - "__RB_DeployBranch__"
    paths-ignore:
      - ".github/**"
  pull_request:
    types:
      - opened
      - synchronize
      - reopened
    paths-ignore:
      - ".github/**"

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines.yml@v4
WORKFLOWEOF
  sed -i.bak "s|__RB_DeployBranch__|${RB_DeployBranch}|g" "$WF_DIR/pipelines.yml"
  rm -f "$WF_DIR/pipelines.yml.bak"
  log_info "Wrote .github/workflows/pipelines.yml"
fi

if should_write pipelines-unlock.yml; then
  cat > "$WF_DIR/pipelines-unlock.yml" <<'WORKFLOWEOF'
# Gruntwork Pipelines Unlock Workflow. Manually unlock a state file left locked by a cancelled or crashed run.
# Trigger from Actions, Pipelines Unlock, Run workflow. Docs: https://docs.gruntwork.io/2.0/docs/pipelines/guides/unlocking-state

name: Pipelines Unlock
run-name: "[GWP]: Pipelines Unlock"
on:
  workflow_dispatch:
    inputs:
      lock_id:
        description: "The ID of the lock, usually a GUID. This is generally found in the console output when Terraform/OpenTofu command fails due to a timeout waiting to acquire a lock. (required if not running unlock_all)"
        required: false
        type: string
      unit_path:
        description: "Path to the Terragrunt Unit directory where the lock is held (everything up to but not including terragrunt.hcl - required if not running unlock_all)"
        required: false
        type: string
      stack_path:
        description: "Path to a Terragrunt Stack directory (everything up to but not including terragrunt.stack.hcl) that generates content required to run unlock in a specified Terragrunt Unit"
        required: false
        type: string
      unlock_all:
        description: "Forcibly reset all locks by deleting the dynamodb table"
        required: false
        type: boolean

permissions:
  id-token: write # Required to assume OIDC roles and create pull requests
  actions: read # Required to manage artifacts via REST API

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-unlock.yml@v4
    with:
      lock_id: ${{ "{{" }} inputs.lock_id {{ "}}" }}
      unit_path: ${{ "{{" }} inputs.unit_path {{ "}}" }}
      unlock_all: ${{ "{{" }} inputs.unlock_all {{ "}}" }}
      stack_path: ${{ "{{" }} inputs.stack_path {{ "}}" }}
WORKFLOWEOF
  log_info "Wrote .github/workflows/pipelines-unlock.yml"
fi

if should_write pipelines-drift-detection.yml; then
  cat > "$WF_DIR/pipelines-drift-detection.yml" <<'WORKFLOWEOF'
# Gruntwork Pipelines Drift Detection workflow. Runs `terragrunt plan` across units and opens PRs for any drift found.
# Enable scheduled runs by uncommenting the cron below. Docs: https://docs.gruntwork.io/2.0/docs/pipelines/guides/running-drift-detection

name: Pipelines Drift Detection
run-name: "[GWP]: Pipelines Drift Detection"
on:
  # Uncomment to enable scheduled Drift Detection
  # schedule:
  #  - cron: '15 12 * * 1'
  workflow_dispatch:
    inputs:
      pipelines_drift_detection_filter:
        description: Limit drift detection to units matching filter https://docs.gruntwork.io/2.0/docs/pipelines/guides/running-drift-detection#drift-detection-filter
        type: string
      pipelines_drift_detection_branch:
        description: The branch name used for drift remediation PRs
        default: drift-detection
        type: string

permissions:
  id-token: write # Required to assume OIDC roles when using default GITHUB_TOKEN
  actions: read # Required to manage artifacts via REST API when using default GITHUB_TOKEN

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-drift-detection.yml@v4
    with:
      pipelines_drift_detection_filter: ${{ "{{" }} inputs.pipelines_drift_detection_filter {{ "}}" }}
      pipelines_drift_detection_branch: ${{ "{{" }} inputs.pipelines_drift_detection_branch {{ "}}" }}
WORKFLOWEOF
  log_info "Wrote .github/workflows/pipelines-drift-detection.yml"
fi

log_info "CI workflow setup complete."
)

# --- Write the repository README ---------------------------------
phase_write_readme() (
# A README that is still the stub GitHub creates with a new repository — a heading, maybe a one-line
# description, nothing else — carries no information worth keeping, and leaving it in place means the
# repository is left undocumented. Anything with real structure (sections, code, lists, links, tables)
# is somebody's work and is never touched.
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


if [ -z "${REPO_FILES:-}" ]; then
  log_error "No repository worktree found. Complete the clone step first."
  exit 1
fi

cd "$REPO_FILES"

TARGET="README.md"
if [ -f README.md ]; then
  if readme_is_stub README.md; then
    log_warn "README.md is still the stub created with the repository; replacing it."
    log_warn "Replacing this content:"
    while IFS= read -r line; do log_warn "    ${line}"; done < README.md
    TITLE=$(head -1 README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
  else
    # A README with real content belongs to whoever wrote it. Write the generated one alongside it
    # instead, so nothing is lost and the choice of whether to adopt it stays with the reader.
    TARGET="README.template.md"
    TITLE=$(grep -m1 -E '^#[[:space:]]' README.md | sed -e 's/^#[[:space:]]*//' -e 's/[[:space:]]*$//')
    log_info "README.md already exists and has real content; leaving it untouched."
    log_info "Writing the generated documentation to README.template.md instead."
  fi
fi
[ -n "${TITLE:-}" ] || TITLE="infrastructure-live"

# Which IaC binary this repository runs, as recorded for Pipelines.
TOOL="opentofu"
if [ -f .gruntwork/repository.hcl ] && grep -q 'tf_binary' .gruntwork/repository.hcl; then
  recorded=$(sed -n 's/.*tf_binary[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .gruntwork/repository.hcl | head -1)
  [ -n "$recorded" ] && TOOL="$recorded"
fi

cat > "$TARGET" <<'READMEEOF'
# __RB_TITLE__

Infrastructure [repo](https://docs.terragrunt.com/guides/ci-with-terragrunt/terragrunt-scale/#repository-structure) for this organization, managed with [Terragrunt Scale](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview) and deployed by [Gruntwork Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview).

```
████████╗███████╗██████╗ ██████╗  █████╗  ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║   ██║████╗  ██║╚══██╔══╝
   ██║   █████╗  ██████╔╝██████╔╝███████║██║  ███╗██████╔╝██║   ██║██╔██╗ ██║   ██║
   ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║
   ██║   ███████╗██║  ██║██║  ██║██║  ██║╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║   ██║
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝
                                                                           ▄▄▄
                    ███████╗ ██████╗ █████╗ ██╗     ███████╗             ▄▀░░░▀▄
                    ██╔════╝██╔════╝██╔══██╗██║     ██╔════╝           ▄▀░░░░░░░▀▄
                    ███████╗██║     ███████║██║     █████╗           ▄▀░░░░░░░░░░░▀▄
                    ╚════██║██║     ██╔══██║██║     ██╔══╝           █▀▄░░░░░░░░░▄▀█
                    ███████║╚██████╗██║  ██║███████╗███████╗         █▓▓▀▄░░░░░▄▀▒▒█
                    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝         █▓▓▓▓▀▄▄▄▀▒▒▒▒█
By Gruntwork                                                          ▀▄▓▓▓▓█▒▒▒▒▄▀
                                                                        ▀▄▓▓█▒▒▄▀
                                                                          ▀▄█▄▀
```

Changes are made by pull request. Opening one runs `terragrunt plan`; merging to `__RB_BRANCH__`
runs `terragrunt apply`. Nothing is applied from a laptop in normal operation.

## Repository layout

```
.
├── README.md
├── root.hcl
├── .mise.toml
├── .gitignore
├── pipelines-bootstrap-example.svg
├── .gruntwork/
│   ├── repository.hcl
│   └── environment-<account>.hcl
├── .github/
│   └── workflows/
│       ├── pipelines.yml
│       ├── pipelines-unlock.yml
│       └── pipelines-drift-detection.yml
└── <account>/
    ├── README.md
    ├── pipelines-bootstrap.svg
    ├── account.hcl
    └── _global/
        ├── region.hcl
        └── bootstrap/
            └── terragrunt.stack.hcl
```

| Path | What it is |
| --- | --- |
| `README.md` | This document |
| `root.hcl` | Root Terragrunt config: remote state, providers, shared inputs |
| `.mise.toml` | Pinned tool versions (Terragrunt, __RB_TOOL__) |
| `.gruntwork/repository.hcl` | Repository-wide Pipelines settings: deploy branch, `tf_binary` |
| `.gruntwork/environment-<account>.hcl` | Which account this environment deploys into, and the roles to assume |
| `.github/workflows/pipelines.yml` | Plan on pull requests, apply on merge to `__RB_BRANCH__` |
| `.github/workflows/pipelines-unlock.yml` | Manually release a stuck state lock |
| `.github/workflows/pipelines-drift-detection.yml` | Scheduled drift detection, if enabled |
| `pipelines-bootstrap-example.svg` | The illustration in the bootstrap section below |
| `<account>/README.md` | What this account's bootstrap provisioned, with its identifiers |
| `<account>/pipelines-bootstrap.svg` | The same, drawn with this account's real values |
| `<account>/account.hcl` | Account-level values: account id, state bucket |
| `<account>/_global/region.hcl` | Region-level values for global resources |
| `<account>/_global/bootstrap/` | The bootstrap stack (see below) |

Each additional account is another top-level directory with the same shape, plus its own
`.gruntwork/environment-<account>.hcl`.

## How the pieces fit

**`root.hcl`** is included by every unit. It configures the remote state backend — one state file per
unit, keyed by its path — and the provider blocks. Change it only when something applies to the whole
repository.

**`.gruntwork/repository.hcl`** is Pipelines' repository-wide configuration: the deploy branch, and
`tf_binary` (this repository uses **__RB_TOOL__**). `.gruntwork/environment-<account>.hcl` maps an
environment to the cloud account it deploys into and the roles Pipelines assumes for plan and apply.

**The bootstrap stack** (`<account>/_global/bootstrap/terragrunt.stack.hcl`) provisions what
Pipelines needs before it can deploy anything into the account:

- an IAM OpenID Connect provider trusting GitHub Actions,
- `__RB_PREFIX__-plan` — read-only, assumed on pull requests,
- `__RB_PREFIX__-apply` — assumed on merges to the deploy branch,
- the S3 bucket holding this account's state.

![Example bootstrap topology](pipelines-bootstrap-example.svg)

*Example labels. Every account bootstrapped into this repository also gets its own copy of this
diagram, drawn with that account's real identifiers, at `<account>/pipelines-bootstrap.svg`.*

It is applied once, when the account is onboarded. After that it is ordinary configuration: changes
to it go through the same plan/apply flow as anything else.

**The workflows** call Gruntwork's reusable workflow rather than containing the logic themselves, so
upgrading Pipelines is a version bump in `.github/workflows/pipelines.yml`.

**`.mise.toml`** pins the tool versions. CI installs exactly these, so a local run matches CI. Run
`mise trust` then `mise install` once after cloning.

## Working in this repository

```bash
mise trust                      # allow mise to load this repo's config
mise install                    # install the pinned tool versions
cd <account>/_global/bootstrap
terragrunt run --all plan       # see what would change
```

Open a pull request with your change and let Pipelines plan it. Read the plan in the PR comment
before merging — merging is what applies it.

## Adding another account

Re-run the Gruntwork Runbook that created this repository and give it a new account name. It adds a
new top-level directory and a new `.gruntwork/environment-<account>.hcl`, and leaves everything here
untouched.

## Reference

- [Pipelines overview](https://docs.gruntwork.io/2.0/docs/pipelines/concepts/overview)
- [Configuration as code reference](https://docs.gruntwork.io/2.0/reference/pipelines/configurations-as-code/api)
- [Terragrunt documentation](https://terragrunt.gruntwork.io)
READMEEOF

sed -i.bak \
  -e "s|__RB_TITLE__|${TITLE}|g" \
  -e "s|__RB_BRANCH__|${RB_DeployBranch}|g" \
  -e "s|__RB_PREFIX__|${RB_OIDCResourcePrefix}|g" \
  -e "s|__RB_TOOL__|${TOOL}|g" "$TARGET"
rm -f "$TARGET.bak"



# The illustration for the README's bootstrap section. Unlike the per-account diagrams this one is
# fixed: it shows the shape of the thing with placeholder labels, so it is written once and never
# needs regenerating. It is committed with the README that references it.
#
# ASCII only: the app's SVG preview does btoa(svgText), which throws above U+00FF and then renders
# nothing. Angle brackets in the placeholder labels are written as entities.
write_example_diagram() {
  cat > pipelines-bootstrap-example.svg <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="760" height="560" viewBox="0 0 760 560" font-family="Helvetica, Arial, sans-serif">
  <rect width="760" height="560" fill="#ffffff"/>
  <text x="380" y="34" text-anchor="middle" font-size="17" font-weight="bold" fill="#1a1a1a">Gruntwork Pipelines bootstrap</text>
  <text x="380" y="54" text-anchor="middle" font-size="12" fill="#666666">what the stack provisions in each AWS account</text>

  <rect x="130" y="80" width="500" height="62" rx="6" fill="#f4f6f8" stroke="#5b6b7c" stroke-width="1.5"/>
  <text x="380" y="103" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">GitHub Actions</text>
  <text x="380" y="121" text-anchor="middle" font-size="11" fill="#444444">&lt;org&gt;/&lt;repo&gt;</text>
  <text x="380" y="136" text-anchor="middle" font-size="11" fill="#444444">deploy branch: &lt;deploy-branch&gt;</text>

  <line x1="380" y1="142" x2="380" y2="182" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="392" y="167" font-size="10" fill="#666666">OIDC token</text>

  <rect x="190" y="182" width="380" height="66" rx="6" fill="#fdf3e3" stroke="#c98a1b" stroke-width="1.5"/>
  <text x="380" y="205" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">IAM OIDC provider</text>
  <text x="380" y="223" text-anchor="middle" font-size="11" fill="#444444">token.actions.githubusercontent.com</text>
  <text x="380" y="239" text-anchor="middle" font-size="11" fill="#444444">audience: sts.amazonaws.com</text>

  <line x1="300" y1="248" x2="190" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="460" y1="248" x2="570" y2="300" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="20" y="304" width="350" height="86" rx="6" fill="#eef5ee" stroke="#3f7d43" stroke-width="1.5"/>
  <text x="195" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Plan role</text>
  <text x="195" y="346" text-anchor="middle" font-size="10" fill="#444444">&lt;prefix&gt;-plan</text>
  <text x="195" y="364" text-anchor="middle" font-size="10" fill="#666666">assumed on pull requests</text>
  <text x="195" y="380" text-anchor="middle" font-size="10" fill="#666666">read only</text>

  <rect x="390" y="304" width="350" height="86" rx="6" fill="#fdeeee" stroke="#a63c3c" stroke-width="1.5"/>
  <text x="565" y="327" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">Apply role</text>
  <text x="565" y="346" text-anchor="middle" font-size="10" fill="#444444">&lt;prefix&gt;-apply</text>
  <text x="565" y="364" text-anchor="middle" font-size="10" fill="#666666">assumed on merges to the deploy branch</text>
  <text x="565" y="380" text-anchor="middle" font-size="10" fill="#666666">creates and changes infrastructure</text>

  <line x1="195" y1="390" x2="330" y2="446" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>
  <line x1="565" y1="390" x2="430" y2="446" stroke="#5b6b7c" stroke-width="1.5" marker-end="url(#arrow)"/>

  <rect x="210" y="450" width="340" height="66" rx="6" fill="#eef2f8" stroke="#3f5f8d" stroke-width="1.5"/>
  <text x="380" y="473" text-anchor="middle" font-size="13" font-weight="bold" fill="#1a1a1a">S3 state bucket</text>
  <text x="380" y="491" text-anchor="middle" font-size="11" fill="#444444">&lt;state-bucket&gt;</text>
  <text x="380" y="507" text-anchor="middle" font-size="10" fill="#666666">one state file per unit</text>

  <text x="380" y="540" text-anchor="middle" font-size="10" fill="#999999">Example. Each account has its own diagram at &lt;account&gt;/pipelines-bootstrap.svg</text>

  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/>
    </marker>
  </defs>
</svg>
SVGEOF
  log_info "Wrote pipelines-bootstrap-example.svg (illustrates the README's bootstrap section)."
}

write_example_diagram

# With the environment name out of the document, bootstrapping another one into this repository
# renders exactly the same README. Dropping an identical README.template.md beside it keeps repeat
# runs from leaving a file that says nothing new. Compared before the banner is prepended.
if [ "$TARGET" = "README.template.md" ] && [ -f README.md ] && cmp -s "$TARGET" README.md; then
  rm -f "$TARGET"
  log_info "README.md is already this document; nothing to add."
  exit 0
fi

if [ "$TARGET" = "README.template.md" ]; then
  # Say what this file is, at the top, so nobody has to guess where it came from.
  tmp=$(mktemp)
  {
    printf '%s\n' "<!--"
    printf '%s\n' "  Generated by the Gruntwork Runbook that set up this repository."
    printf '%s\n' ""
    printf '%s\n' "  Your repository already had a README, so this was written alongside it rather than over it."
    printf '%s\n' "  Adopt it with:  mv README.template.md README.md"
    printf '%s\n' "  Or take the parts you want and delete the rest — nothing depends on this file."
    printf '%s\n' "-->"
    printf '%s\n' ""
    cat "$TARGET"
  } > "$tmp" && mv "$tmp" "$TARGET"
  log_info "Wrote README.template.md alongside your README.md. Review it, then rename it over README.md"
  log_info "if you want it, or delete it — nothing depends on it."
  exit 0
fi

log_info "Wrote README.md describing the repository layout, bootstrap stack, workflows and Pipelines config."
exit 0
)


# ---------------------------------------------------------------------------
# Run them in order
# ---------------------------------------------------------------------------

run_phase() {
  title=$1; fn=$2
  log_info ""
  log_info "=== ${title} ==="
  set +e
  "$fn"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    log_error "${title} failed (exit ${rc})."
    log_error "The phases after it did not run. Fix the problem and run this step again."
    exit "$rc"
  fi
}

run_phase "Render the Terragrunt Scale configuration" phase_generate
run_phase "Install the pinned tool dependencies" phase_install_deps
run_phase "Add the Pipelines CI workflows" phase_add_ci_workflows
run_phase "Write the repository README" phase_write_readme

log_info ""
log_info "Repository set up: configuration rendered, tools installed, CI workflows and README written."
exit 0
