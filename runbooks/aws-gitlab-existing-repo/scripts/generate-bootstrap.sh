#!/bin/bash
# Render the aws/gitlab/account boilerplate template into the cloned repository, using values
# collected from the form and auto-derived from AWS. Runs non-interactively.
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

RB_AWSRegion=$(rb_unquote "{{ .inputs.AWSRegion }}")
RB_AccountName=$(rb_unquote "{{ .inputs.AccountName }}")
RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_GitLabGroupName=$(rb_unquote "{{ .inputs.GitLabGroupName }}")
RB_GitLabProjectName=$(rb_unquote "{{ .inputs.GitLabProjectName }}")
RB_Issuer=$(rb_unquote "{{ .inputs.Issuer }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_out_derive_aws_aws_account_id=$(rb_unquote "{{ .outputs.derive_aws.aws_account_id }}")
RB_out_derive_aws_partition=$(rb_unquote "{{ .outputs.derive_aws.partition }}")
RB_out_resolve_catalog_ref_catalog_ref=$(rb_unquote "{{ .outputs.resolve_catalog_ref.catalog_ref }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

cd "$REPO_FILES"

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
# "default" is the form's sentinel for "gitlab.com"; a blank input would gate the block.
ISSUER="${RB_Issuer}"
if [ "$ISSUER" = "default" ]; then ISSUER=""; fi

log_info "Writing vars.yml for the AWS account bootstrap..."
cat > vars.yml <<EOF
AccountName: "${RB_AccountName}"
AWSAccountID: "${RB_out_derive_aws_aws_account_id}"
AWSRegion: "${RB_AWSRegion}"
StateBucketName: "${RB_StateBucketName}"
Partition: "${RB_out_derive_aws_partition}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
GitLabGroupName: "${RB_GitLabGroupName}"
GitLabProjectName: "${RB_GitLabProjectName}"
DeployBranch: "${RB_DeployBranch}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
EOF

# Issuer is only needed for self-hosted GitLab; include it only when provided so the template
# falls back to its computed gitlab.com issuer otherwise.
if [ -n "$ISSUER" ]; then
  echo "Issuer: \"${ISSUER}\"" >> vars.yml
fi

log_info "Rendering aws/gitlab/account template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/gitlab/account?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

# Existing repos may not already ignore Terragrunt's local caches; make sure we never commit them.
touch .gitignore
grep -qxF '.terragrunt-cache' .gitignore || echo '.terragrunt-cache' >> .gitignore
grep -qxF '.terragrunt-stack' .gitignore || echo '.terragrunt-stack' >> .gitignore

log_info "Generated ${RB_AccountName}/_global/bootstrap/ and .gruntwork/environment-${RB_AccountName}.hcl"

# Ensure the repository-wide Gruntwork Pipelines config exists. The account/project/subscription template
# does NOT create .gruntwork/repository.hcl (only infrastructure-live does), so an existing repo adopting
# Pipelines needs it here. Written only if absent, so bootstrapping another account into a repo that
# already has Pipelines will not clobber (or revert customizations to) its repository.hcl.
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

exit 0
