resource "azurerm_role_assignment" "role_assignment" {
  for_each = var.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = var.principal_id
  description          = each.value.description
  condition            = each.value.condition
  condition_version    = each.value.condition == null ? null : coalesce(each.value.condition_version, "2.0")
}
