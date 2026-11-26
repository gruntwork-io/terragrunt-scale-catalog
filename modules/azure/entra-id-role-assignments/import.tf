# Adopts an assignment that already gives the principal the same role at the same scope, such as one
# made with the Azure CLI, instead of failing on a second create. Import blocks only work in a root
# module, so call this module from a unit, not from another module.

data "azurerm_role_definition" "existing" {
  for_each = var.import_existing ? var.role_assignments : {}

  name  = each.value.role_definition_name
  scope = each.value.scope
}

data "azurerm_role_assignments" "existing" {
  for_each = var.import_existing ? var.role_assignments : {}

  scope          = each.value.scope
  principal_id   = var.principal_id
  limit_at_scope = true
}

locals {
  existing_role_assignment_ids = {
    for key, found in data.azurerm_role_assignments.existing : key => [
      for assignment in found.role_assignments : assignment.role_assignment_id
      if lower(assignment.role_assignment_scope) == lower(var.role_assignments[key].scope)
      && endswith(lower(assignment.role_definition_id), lower(data.azurerm_role_definition.existing[key].role_definition_id))
    ]
  }
}

# Once an assignment is in state, OpenTofu skips its import block.
import {
  for_each = { for key, ids in local.existing_role_assignment_ids : key => ids[0] if length(ids) > 0 }

  to = azurerm_role_assignment.role_assignment[each.key]
  id = each.value
}
