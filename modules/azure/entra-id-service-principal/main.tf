data "azuread_client_config" "current" {}

resource "azuread_service_principal" "service_principal" {
  client_id = var.client_id

  app_role_assignment_required = true

  // The principal that creates the service principal owns it. Later runs ignore owners, so a plan does not
  // change them to whoever runs it, such as a Pipelines identity after a person ran the first apply.
  owners = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [owners]
  }
}
