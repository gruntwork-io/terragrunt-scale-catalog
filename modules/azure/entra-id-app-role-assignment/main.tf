data "azuread_service_principal" "resource" {
  client_id = var.resource_client_id
}

resource "azuread_app_role_assignment" "app_role_assignment" {
  for_each = toset(var.app_roles)

  app_role_id         = data.azuread_service_principal.resource.app_role_ids[each.value]
  principal_object_id = var.principal_object_id
  resource_object_id  = data.azuread_service_principal.resource.object_id
}
