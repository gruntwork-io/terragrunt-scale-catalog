include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/entra-id-service-principal"

  update_source_with_cas = true
}

dependency "app" {
  config_path = values.app_config_path

  mock_outputs = {
    client_id = "12345678-1234-1234-1234-123456789012"
  }
}

inputs = {
  client_id = dependency.app.outputs.client_id
}
