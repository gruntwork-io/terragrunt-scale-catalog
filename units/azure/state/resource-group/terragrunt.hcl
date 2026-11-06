include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/resource-group"

  update_source_with_cas = true
}

inputs = {
  name     = values.name
  location = values.location
}
