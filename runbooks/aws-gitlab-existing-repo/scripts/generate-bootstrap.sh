#!/bin/bash
# Render the aws/gitlab/account boilerplate template into the cloned repository, using values
# collected from the form and auto-derived from AWS. Runs non-interactively.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

cd "$REPO_FILES"

# Prefer an explicit override from the form; else the latest release resolved in the previous
# step; else a known-good pinned fallback.
CATALOG_REF="{{ .inputs.TerragruntScaleCatalogRef }}"
if [ -z "$CATALOG_REF" ]; then
  CATALOG_REF="{{ .outputs.resolve_catalog_ref.catalog_ref }}"
fi
if [ -z "$CATALOG_REF" ]; then
  CATALOG_REF="v1.13.1"
fi
log_info "Using terragrunt-scale-catalog ref: ${CATALOG_REF}"
ISSUER="{{ .inputs.Issuer }}"

log_info "Writing vars.yml for the AWS account bootstrap..."
cat > vars.yml <<EOF
AccountName: "{{ .inputs.AccountName }}"
AWSAccountID: "{{ .outputs.derive_aws.aws_account_id }}"
AWSRegion: "{{ .inputs.AWSRegion }}"
StateBucketName: "{{ .inputs.StateBucketName }}"
Partition: "{{ .outputs.derive_aws.partition }}"
OIDCResourcePrefix: "{{ .inputs.OIDCResourcePrefix }}"
GitLabGroupName: "{{ .inputs.GitLabGroupName }}"
GitLabProjectName: "{{ .inputs.GitLabProjectName }}"
DeployBranch: "{{ .inputs.DeployBranch }}"
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

log_info "Generated {{ .inputs.AccountName }}/_global/bootstrap/ and .gruntwork/environment-{{ .inputs.AccountName }}.hcl"

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
  deploy_branch_name = "{{ .inputs.DeployBranch }}"

  // Controls whether each push creates a new status comment or updates the existing one in-place.
  status_update {
    new_comment_per_push = false
  }

  env {
    PIPELINES_FEATURE_EXPERIMENT_IGNORE_UNITS_WITHOUT_ENVIRONMENT = "true"
  }
}
REPOEOF
  log_info "Wrote .gruntwork/repository.hcl (deploy branch: {{ .inputs.DeployBranch }})"
fi

exit 0
