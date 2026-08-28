#!/bin/bash
# Render the azure/gitlab/infrastructure-live boilerplate template into the cloned repository,
# using values collected from the form and auto-derived from Azure. Runs non-interactively.
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

RB_AzureLocation=$(rb_unquote "{{ .inputs.AzureLocation }}")
RB_DeployBranch=$(rb_unquote "{{ .inputs.DeployBranch }}")
RB_GitLabGroupName=$(rb_unquote "{{ .inputs.GitLabGroupName }}")
RB_GitLabProjectName=$(rb_unquote "{{ .inputs.GitLabProjectName }}")
RB_IncludeDriftDetection=$(rb_unquote "{{ .inputs.IncludeDriftDetection }}")
RB_Issuer=$(rb_unquote "{{ .inputs.Issuer }}")
RB_out_derive_azure_azure_subscription_id=$(rb_unquote "{{ .outputs.derive_azure.azure_subscription_id }}")
RB_out_derive_azure_azure_tenant_id=$(rb_unquote "{{ .outputs.derive_azure.azure_tenant_id }}")
RB_out_resolve_catalog_ref_catalog_ref=$(rb_unquote "{{ .outputs.resolve_catalog_ref.catalog_ref }}")
# "default" is the form's sentinel for the provider default; the template expects an empty
# string there, and a blank input would gate this block on an unmet dependency.
if [ "$RB_Issuer" = "default" ]; then RB_Issuer=""; fi
RB_OIDCResourcePrefix=$(rb_unquote "{{ .inputs.OIDCResourcePrefix }}")
RB_OpenTofuVersion=$(rb_unquote "{{ .inputs.OpenTofuVersion }}")
RB_StateResourceGroupName=$(rb_unquote "{{ .inputs.StateResourceGroupName }}")
RB_StateStorageAccountName=$(rb_unquote "{{ .inputs.StateStorageAccountName }}")
RB_StateStorageContainerName=$(rb_unquote "{{ .inputs.StateStorageContainerName }}")
RB_SubscriptionName=$(rb_unquote "{{ .inputs.SubscriptionName }}")
RB_TerragruntScaleCatalogRef=$(rb_unquote "{{ .inputs.TerragruntScaleCatalogRef }}")
RB_TerragruntVersion=$(rb_unquote "{{ .inputs.TerragruntVersion }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the 'Clone the repository' step first."
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

log_info "Writing vars.yml for the Azure + GitLab infrastructure-live scaffold..."
cat >vars.yml <<EOF
SubscriptionName: "${RB_SubscriptionName}"
GitLabGroupName: "${RB_GitLabGroupName}"
GitLabProjectName: "${RB_GitLabProjectName}"
AzureLocation: "${RB_AzureLocation}"
DeployBranch: "${RB_DeployBranch}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
OIDCResourcePrefix: "${RB_OIDCResourcePrefix}"
Issuer: "${RB_Issuer}"
IncludeDriftDetection: ${RB_IncludeDriftDetection}
AzureTenantID: "${RB_out_derive_azure_azure_tenant_id}"
AzureSubscriptionID: "${RB_out_derive_azure_azure_subscription_id}"
StateResourceGroupName: "${RB_StateResourceGroupName}"
StateStorageAccountName: "${RB_StateStorageAccountName}"
StateStorageContainerName: "${RB_StateStorageContainerName}"
TerragruntVersion: "${RB_TerragruntVersion}"
OpenTofuVersion: "${RB_OpenTofuVersion}"
EOF

log_info "Rendering azure/gitlab/infrastructure-live template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/gitlab/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

echo "generated=true" >>"$RUNBOOK_OUTPUT"
log_info "Generated root.hcl, .gitlab-ci.yml, .mise.toml, and ${RB_SubscriptionName}/bootstrap/."
log_info "Also generated .gruntwork/environment-${RB_SubscriptionName}.hcl (client IDs filled in later)."
exit 0
