resource "azuread_service_principal" "service_principal" {
  client_id = var.client_id

  app_role_assignment_required = true

  owners = var.owners
}
