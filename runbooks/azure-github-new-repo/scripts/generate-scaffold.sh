#!/bin/bash
# Render the azure/github/infrastructure-live boilerplate template into the newly cloned (empty)
# repository, using values collected from the form and auto-derived from GitHub + Azure. This template
# scaffolds the FULL repository (root.hcl with the azurerm backend commented out, .mise.toml, .gitignore,
# .gruntwork/, the .github/workflows Pipelines workflows, and the first subscription's bootstrap stack).
# Runs non-interactively.
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

log_info "Writing vars.yml for the infrastructure-live scaffold..."
cat > vars.yml <<EOF
IncludeDriftDetection: {{ .inputs.IncludeDriftDetection }}
SubscriptionName: "{{ .inputs.SubscriptionName }}"
GitHubOrgName: "{{ .outputs.clone.repo_owner }}"
GitHubRepoName: "{{ .outputs.clone.repo_name }}"
GitHubOrgID: "{{ .outputs.clone.org_id }}"
GitHubRepoID: "{{ .outputs.clone.repo_id }}"
AzureLocation: "{{ .inputs.AzureLocation }}"
DeployBranch: "{{ .inputs.DeployBranch }}"
TerragruntScaleCatalogRef: "${CATALOG_REF}"
OIDCResourcePrefix: "{{ .inputs.OIDCResourcePrefix }}"
Issuer: "{{ .inputs.Issuer }}"
AzureTenantID: "{{ .outputs.derive_azure.azure_tenant_id }}"
AzureSubscriptionID: "{{ .outputs.derive_azure.azure_subscription_id }}"
StateResourceGroupName: "{{ .inputs.StateResourceGroupName }}"
StateStorageAccountName: "{{ .inputs.StateStorageAccountName }}"
StateStorageContainerName: "{{ .inputs.StateStorageContainerName }}"
TerragruntVersion: "{{ .inputs.TerragruntVersion }}"
OpenTofuVersion: "{{ .inputs.OpenTofuVersion }}"
EOF

log_info "Rendering azure/github/infrastructure-live template (ref ${CATALOG_REF})..."
"${BOILERPLATE_BIN:-boilerplate}" \
  --template-url "github.com/gruntwork-io/terragrunt-scale-catalog//templates/boilerplate/azure/github/infrastructure-live?ref=${CATALOG_REF}" \
  --output-folder . \
  --var-file vars.yml \
  --non-interactive

rm -f vars.yml

echo "scaffold_generated=true" >> "$RUNBOOK_OUTPUT"

log_info "Scaffolded infrastructure-live repository for subscription {{ .inputs.SubscriptionName }}."
exit 0
