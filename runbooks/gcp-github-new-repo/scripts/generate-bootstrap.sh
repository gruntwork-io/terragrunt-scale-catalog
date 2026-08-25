#!/bin/bash
# Render the gcp/github/infrastructure-live boilerplate template into the cloned repository, using
# values collected from the form and auto-derived from GitHub + GCP. Runs non-interactively.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the repository' step first."
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
IncludeDriftDetection: {{ .inputs.IncludeDriftDetection }}
ProjectName: "{{ .inputs.ProjectName }}"
GCPProjectID: "{{ .inputs.GCPProjectID }}"
GCPProjectNumber: "{{ .outputs.derive_gcp.gcp_project_number }}"
GCPRegion: "{{ .inputs.GCPRegion }}"
StateBucketName: "{{ .inputs.StateBucketName }}"
GitHubOrgName: "{{ .outputs.clone.repo_owner }}"
GitHubRepoName: "{{ .outputs.clone.repo_name }}"
GitHubOrgID: "{{ .outputs.clone.org_id }}"
GitHubRepoID: "{{ .outputs.clone.repo_id }}"
OIDCResourcePrefix: "{{ .inputs.OIDCResourcePrefix }}"
DeployBranch: "{{ .inputs.DeployBranch }}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
TerragruntVersion: "{{ .inputs.TerragruntVersion }}"
OpenTofuVersion: "{{ .inputs.OpenTofuVersion }}"
EOF

log_info "Rendering gcp/github/infrastructure-live template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/github/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

log_info "Generated root.hcl, the GitHub Actions workflows, {{ .inputs.ProjectName }}/bootstrap/, and .gruntwork/environment-{{ .inputs.ProjectName }}.hcl"
exit 0
