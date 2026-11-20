include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/entra-id-flexible-federated-identity-credential"

  update_source_with_cas = true
}

dependency "app" {
  config_path = values.app_config_path

  mock_outputs = {
    id = "/applications/12345678-1234-1234-1234-123456789012"
  }
}

inputs = {
  application_id = dependency.app.outputs.id

  display_name = values.display_name
  description  = values.description

  audiences = values.audiences
  issuer    = values.issuer

  claims_matching_expression_value = values.claims_matching_expression_value
}
