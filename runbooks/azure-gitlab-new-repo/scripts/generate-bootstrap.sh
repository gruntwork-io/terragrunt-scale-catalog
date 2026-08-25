#!/bin/bash
# Render the azure/gitlab/infrastructure-live boilerplate template into the cloned repository,
# using values collected from the form and auto-derived from Azure. Runs non-interactively.
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

log_info "Writing vars.yml for the Azure + GitLab infrastructure-live scaffold..."
cat >vars.yml <<EOF
SubscriptionName: "{{ .inputs.SubscriptionName }}"
GitLabGroupName: "{{ .inputs.GitLabGroupName }}"
GitLabProjectName: "{{ .inputs.GitLabProjectName }}"
AzureLocation: "{{ .inputs.AzureLocation }}"
DeployBranch: "{{ .inputs.DeployBranch }}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
OIDCResourcePrefix: "{{ .inputs.OIDCResourcePrefix }}"
Issuer: "{{ .inputs.Issuer }}"
IncludeDriftDetection: {{ .inputs.IncludeDriftDetection }}
AzureTenantID: "{{ .outputs.derive_azure.azure_tenant_id }}"
AzureSubscriptionID: "{{ .outputs.derive_azure.azure_subscription_id }}"
StateResourceGroupName: "{{ .inputs.StateResourceGroupName }}"
StateStorageAccountName: "{{ .inputs.StateStorageAccountName }}"
StateStorageContainerName: "{{ .inputs.StateStorageContainerName }}"
TerragruntVersion: "{{ .inputs.TerragruntVersion }}"
OpenTofuVersion: "{{ .inputs.OpenTofuVersion }}"
EOF

log_info "Rendering azure/gitlab/infrastructure-live template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/gitlab/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

echo "generated=true" >>"$RUNBOOK_OUTPUT"
log_info "Generated root.hcl, .gitlab-ci.yml, .mise.toml, and {{ .inputs.SubscriptionName }}/bootstrap/."
log_info "Also generated .gruntwork/environment-{{ .inputs.SubscriptionName }}.hcl (client IDs filled in later)."
exit 0
