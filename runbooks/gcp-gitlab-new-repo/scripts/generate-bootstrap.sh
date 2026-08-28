#!/bin/bash
# Render the gcp/gitlab/infrastructure-live boilerplate template into the cloned repository, using values
# collected from the form and the auto-derived GCP project number. Runs non-interactively.
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

RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_GCPRegion=$(rb_unquote "{{ .inputs.GCPRegion }}")
RB_GitLabGroupName=$(rb_unquote "{{ .inputs.GitLabGroupName }}")
RB_GitLabProjectName=$(rb_unquote "{{ .inputs.GitLabProjectName }}")
RB_GitLabServerDomain=$(rb_unquote "{{ .inputs.GitLabServerDomain }}")
RB_out_derive_gcp_gcp_project_number=$(rb_unquote "{{ .outputs.derive_gcp.gcp_project_number }}")
RB_out_resolve_catalog_ref_catalog_ref=$(rb_unquote "{{ .outputs.resolve_catalog_ref.catalog_ref }}")
# "default" is the form's sentinel for gitlab.com; the template expects an empty string there,
# and a blank input would gate this block on an unmet dependency.
if [ "$RB_GitLabServerDomain" = "default" ]; then RB_GitLabServerDomain=""; fi
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the new repository' step first."
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

log_info "Writing vars.yml for the GCP infrastructure-live scaffold..."
cat > vars.yml <<EOF
ProjectName: "${RB_ProjectName}"
GCPProjectID: "${RB_GCPProjectID}"
GCPProjectNumber: "${RB_out_derive_gcp_gcp_project_number}"
GCPRegion: "${RB_GCPRegion}"
StateBucketName: "${RB_StateBucketName}"
GitLabGroupName: "${RB_GitLabGroupName}"
GitLabProjectName: "${RB_GitLabProjectName}"
GitLabServerDomain: "${RB_GitLabServerDomain}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
DeployBranch: "${RB_DeployBranch}"
IncludeDriftDetection: ${RB_IncludeDriftDetection}
TerragruntScaleCatalogRef: "${CATALOG_REF}"
TerragruntVersion: "${RB_TerragruntVersion}"
OpenTofuVersion: "${RB_OpenTofuVersion}"
EOF

log_info "Rendering gcp/gitlab/infrastructure-live template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/gitlab/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

echo "bootstrap_dir=${RB_ProjectName}/bootstrap" >> "$RUNBOOK_OUTPUT"

log_info "Generated the repository scaffold, including .gitlab-ci.yml and ${RB_ProjectName}/bootstrap/."
exit 0
