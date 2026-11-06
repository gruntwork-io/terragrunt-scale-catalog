include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/storage-account"

  update_source_with_cas = true
}

dependency "resource_group" {
  config_path = values.resource_group_config_path

  mock_outputs = {
    name = "mockname"
  }
}

inputs = {
  name     = values.name
  location = values.location

  resource_group_name = dependency.resource_group.outputs.name
}
