#!/bin/bash
# Render the Terragrunt Scale configuration into the cloned repository. Which template is used
# depends on the repository's shape, decided by the 'Check the repository' step:
#
#   scaffold - gcp/github/infrastructure-live. Renders the whole repository: root.hcl, .mise.toml,
#              .gitignore, .gruntwork/, the GitHub Actions workflows, and the first project's stack.
#   project  - gcp/github/project. Adds only the new project's directory and bootstrap stack to a
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
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_IaCTool=$(rb_unquote "{{ .inputs.IaCTool }}")
RB_TerraformVersion=$(rb_unquote "{{ .inputs.TerraformVersion }}")
RB_out_inspect_repository_repo_mode=$(rb_unquote "{{ .outputs.inspect_repository.repo_mode }}")
RB_ProjectName=$(rb_unquote "{{ .inputs.ProjectName }}")
RB_StateBucketName=$(rb_unquote "{{ .inputs.StateBucketName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_out_clone_org_id=$(rb_unquote "{{ .outputs.clone.org_id }}")
RB_out_clone_repo_id=$(rb_unquote "{{ .outputs.clone.repo_id }}")
RB_out_clone_repo_name=$(rb_unquote "{{ .outputs.clone.repo_name }}")
RB_out_clone_repo_owner=$(rb_unquote "{{ .outputs.clone.repo_owner }}")
RB_out_derive_gcp_gcp_project_number=$(rb_unquote "{{ .outputs.derive_gcp.gcp_project_number }}")
RB_out_resolve_catalog_ref_catalog_ref=$(rb_unquote "{{ .outputs.resolve_catalog_ref.catalog_ref }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone your repository' step first."
  exit 1
fi

cd "$REPO_FILES"

MODE="${RB_out_inspect_repository_repo_mode}"
case "$MODE" in
  scaffold)        TEMPLATE="infrastructure-live" ;;
  account|project) MODE="project"; TEMPLATE="project" ;;
  *) log_error "Unknown repository mode [${MODE}]. Re-run the repository check in step 4."; exit 1 ;;
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

log_info "Writing vars.yml for the gcp/github/${TEMPLATE} template..."
cat > vars.yml <<EOF
ProjectName: "${RB_ProjectName}"
GCPProjectID: "${RB_GCPProjectID}"
GCPProjectNumber: "${RB_out_derive_gcp_gcp_project_number}"
GCPRegion: "${RB_GCPRegion}"
StateBucketName: "${RB_StateBucketName}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
GitHubOrgName: "${RB_out_clone_repo_owner}"
GitHubRepoName: "${RB_out_clone_repo_name}"
GitHubOrgID: "${RB_out_clone_org_id}"
GitHubRepoID: "${RB_out_clone_repo_id}"
DeployBranch: "${RB_DeployBranch}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
EOF

# Only the full-repository template renders .mise.toml and the CI workflows, so only it takes the
# tool versions, the drift-detection switch and the IaC tool choice.
if [ "$MODE" = "scaffold" ]; then
  cat >> vars.yml <<EOF
IncludeDriftDetection: ${RB_IncludeDriftDetection}
TerragruntVersion: "${RB_TerragruntVersion}"
OpenTofuVersion: "${RB_OpenTofuVersion}"
IaCTool: "${RB_IaCTool}"
TerraformVersion: "${RB_TerraformVersion}"
EOF
fi

log_info "Rendering gcp/github/${TEMPLATE} template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/gcp/github/${TEMPLATE}?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

if [ "$MODE" = "scaffold" ]; then
  log_info "Scaffolded the repository for project ${RB_ProjectName}."
  exit 0
fi

# From here on: adding a project to a repository that already had root.hcl.

# Existing repos may not already ignore Terragrunt's local caches; make sure we never commit them.
touch .gitignore
grep -qxF '.terragrunt-cache' .gitignore || echo '.terragrunt-cache' >> .gitignore
grep -qxF '.terragrunt-stack' .gitignore || echo '.terragrunt-stack' >> .gitignore

log_info "Generated ${RB_ProjectName}/bootstrap/, ${RB_ProjectName}/project.hcl, and .gruntwork/environment-${RB_ProjectName}.hcl"

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
