#!/bin/bash
# Render the Terragrunt Scale configuration into the cloned repository. Which template is used
# depends on the repository's shape, decided by the 'Detect repository layout' check:
#
#   scaffold - aws/github/infrastructure-live. Renders the whole repository: root.hcl, .mise.toml,
#              .gitignore, .gruntwork/, the GitHub Actions workflows, and the first account's stack.
#   account  - aws/github/account. Adds only the new account's directory and bootstrap stack to a
#              repository that already has root.hcl.
#
# Runs non-interactively.
set -euo pipefail

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
RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_IaCTool=$(rb_unquote "{{ .inputs.IaCTool }}")
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
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
RB_out_derive_aws_aws_account_id=$(rb_unquote "{{ .outputs.derive_aws.aws_account_id }}")
RB_out_derive_aws_partition=$(rb_unquote "{{ .outputs.derive_aws.partition }}")
RB_out_inspect_repository_repo_mode=$(rb_unquote "{{ .outputs.inspect_repository.repo_mode }}")
RB_out_resolve_catalog_ref_catalog_ref=$(rb_unquote "{{ .outputs.resolve_catalog_ref.catalog_ref }}")

MODE="${RB_out_inspect_repository_repo_mode}"

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

# Prefer an explicit override from the form; else the latest release resolved in the previous
# step; else a known-good pinned fallback.
# "latest" is the form's default: a non-empty sentinel, because a blank optional input
# leaves the whole block waiting on an unmet dependency and it can never be run.
CATALOG_REF="${RB_TerragruntScaleCatalogRef}"
if [ "$CATALOG_REF" = "latest" ]; then CATALOG_REF=""; fi
if [ -z "$CATALOG_REF" ]; then
  CATALOG_REF="${RB_out_resolve_catalog_ref_catalog_ref}"
fi
if [ -z "$CATALOG_REF" ]; then
  CATALOG_REF="v1.13.1"
fi
log_info "Using terragrunt-scale-catalog ref: ${CATALOG_REF}"

log_info "Writing vars.yml for the aws/github/${TEMPLATE} template..."
cat > vars.yml <<EOF
AccountName: "${RB_AccountName}"
AWSAccountID: "${RB_out_derive_aws_aws_account_id}"
AWSRegion: "${RB_AWSRegion}"
StateBucketName: "${RB_StateBucketName}"
Partition: "${RB_out_derive_aws_partition}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
GitHubOrgName: "${RB_out_clone_repo_owner}"
GitHubRepoName: "${RB_out_clone_repo_name}"
GitHubOrgID: "${RB_out_clone_org_id}"
GitHubRepoID: "${RB_out_clone_repo_id}"
DeployBranch: "${RB_DeployBranch}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
EOF

# Only the full-repository template renders .mise.toml and the CI workflows, so only it takes
# the tool versions and the drift-detection switch.
if [ "$MODE" = "scaffold" ]; then
  cat >> vars.yml <<EOF
IncludeDriftDetection: ${RB_IncludeDriftDetection}
TerragruntVersion: "${RB_TerragruntVersion}"
OpenTofuVersion: "${RB_OpenTofuVersion}"
IaCTool: "${RB_IaCTool}"
TerraformVersion: "${RB_TerraformVersion}"
EOF
fi

log_info "Rendering aws/github/${TEMPLATE} template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/github/${TEMPLATE}?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

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
      sed -i.bak -E 's|^([[:space:]]*)"?opentofu"?[[:space:]]*=.*|\1terraform = "'"${RB_TerraformVersion}"'"|' .mise.toml && rm -f .mise.toml.bak
      grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml \
        && log_info "Pinned terraform ${RB_TerraformVersion} in the rendered .mise.toml." \
        || log_warn "Tried to pin terraform in .mise.toml but the file still does not declare it."
    elif [ "$effective" = "opentofu" ] && grep -qE '^[[:space:]]*"?terraform"?[[:space:]]*=' .mise.toml; then
      sed -i.bak -E 's|^([[:space:]]*)"?terraform"?[[:space:]]*=.*|\1opentofu = "'"${RB_OpenTofuVersion}"'"|' .mise.toml && rm -f .mise.toml.bak
      grep -qE '^[[:space:]]*"?opentofu"?[[:space:]]*=' .mise.toml \
        && log_info "Pinned opentofu ${RB_OpenTofuVersion} in the rendered .mise.toml." \
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

exit 0
