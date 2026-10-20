include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/custom-role-definition"

  update_source_with_cas = true
}

inputs = {
  name        = values.name
  scope       = try(values.scope, null)
  description = values.description

  actions          = values.actions
  not_actions      = try(values.not_actions, [])
  data_actions     = try(values.data_actions, [])
  not_data_actions = try(values.not_data_actions, [])

  assignable_scopes = try(values.assignable_scopes, null)
}

