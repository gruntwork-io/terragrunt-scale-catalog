include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/entra-id-role-assignments"

  update_source_with_cas = true
}

dependency "service_principal" {
  config_path = values.service_principal_config_path

  mock_outputs = {
    object_id    = "00000000-0000-0000-0000-000000000000"
    display_name = "mock-display-name"
  }
}

inputs = {
  principal_id     = dependency.service_principal.outputs.object_id
  role_assignments = try(values.role_assignments, {})
  import_existing  = try(values.import_existing, true)
}
