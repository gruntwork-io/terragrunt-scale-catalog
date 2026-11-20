include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/entra-id-app-role-assignment"

  update_source_with_cas = true
}

dependency "service_principal" {
  config_path = values.service_principal_config_path

  mock_outputs = {
    object_id    = "12345678-1234-1234-1234-123456789012"
    display_name = "mock-display-name"
  }
}

inputs = {
  principal_object_id = dependency.service_principal.outputs.object_id

  app_roles          = values.app_roles
  resource_client_id = try(values.resource_client_id, "00000003-0000-0000-c000-000000000000")
}
