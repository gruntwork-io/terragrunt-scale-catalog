include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/entra-id-application"

  update_source_with_cas = true
}

inputs = {
  display_name = values.display_name
  description  = values.description
}
