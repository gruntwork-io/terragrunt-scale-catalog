#!/bin/bash
# Render the gcp/gitlab/infrastructure-live boilerplate template into the cloned repository, using values
# collected from the form and the auto-derived GCP project number. Runs non-interactively.
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

log_info "Writing vars.yml for the GCP infrastructure-live scaffold..."
cat > vars.yml <<EOF
ProjectName: "{{ .inputs.ProjectName }}"
GCPProjectID: "{{ .inputs.GCPProjectID }}"
GCPProjectNumber: "{{ .outputs.derive_gcp.gcp_project_number }}"
GCPRegion: "{{ .inputs.GCPRegion }}"
StateBucketName: "{{ .inputs.StateBucketName }}"
GitLabGroupName: "{{ .inputs.GitLabGroupName }}"
GitLabProjectName: "{{ .inputs.GitLabProjectName }}"
GitLabServerDomain: "{{ .inputs.GitLabServerDomain }}"
OIDCResourcePrefix: "{{ .inputs.OIDCResourcePrefix }}"
DeployBranch: "{{ .inputs.DeployBranch }}"
IncludeDriftDetection: {{ .inputs.IncludeDriftDetection }}
TerragruntScaleCatalogRef: "${CATALOG_REF}"
TerragruntVersion: "{{ .inputs.TerragruntVersion }}"
OpenTofuVersion: "{{ .inputs.OpenTofuVersion }}"
EOF

log_info "Rendering gcp/gitlab/infrastructure-live template (ref ${CATALOG_REF})..."
boilerplate \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/gitlab/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

echo "bootstrap_dir={{ .inputs.ProjectName }}/bootstrap" >> "$RUNBOOK_OUTPUT"

log_info "Generated the repository scaffold, including .gitlab-ci.yml and {{ .inputs.ProjectName }}/bootstrap/."
exit 0
