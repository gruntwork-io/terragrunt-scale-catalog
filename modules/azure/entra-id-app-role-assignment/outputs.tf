output "ids" {
  description = "The IDs of the app role assignments, keyed by app role value."
  value       = { for app_role, assignment in azuread_app_role_assignment.app_role_assignment : app_role => assignment.id }
}
