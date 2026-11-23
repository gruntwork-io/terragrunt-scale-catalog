resource "azuread_application" "app" {
  display_name = var.display_name
  description  = var.description

  owners = var.owners
}
