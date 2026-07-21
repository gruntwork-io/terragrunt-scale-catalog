#!/bin/bash
# Render the aws/gitlab/infrastructure-live boilerplate template into the newly cloned (empty)
# repository, using values collected from the form and auto-derived from AWS. This template
# scaffolds the FULL repository (root.hcl, .mise.toml, .gitignore, .gruntwork/, the .gitlab-ci.yml
# Pipelines pipeline, and the first account's bootstrap stack). Runs non-interactively.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the new repository' step first."
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

log_info "Writing vars.yml for the infrastructure-live scaffold..."
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
TerragruntVersion: "{{ .inputs.TerragruntVersion }}"
OpenTofuVersion: "{{ .inputs.OpenTofuVersion }}"
EOF

# Issuer is only needed for self-hosted GitLab; include it only when provided so the template
# falls back to its computed gitlab.com issuer otherwise.
if [ -n "$ISSUER" ]; then
  echo "Issuer: \"${ISSUER}\"" >> vars.yml
fi

log_info "Rendering aws/gitlab/infrastructure-live template (ref ${CATALOG_REF})..."
boilerplate \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/aws/gitlab/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

log_info "Scaffolded infrastructure-live repository for account {{ .inputs.AccountName }}."
exit 0
