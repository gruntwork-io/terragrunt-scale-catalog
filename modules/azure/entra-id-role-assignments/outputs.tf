output "role_assignment_ids" {
  description = "The IDs of the role assignments, keyed like role_assignments."
  value       = { for key, assignment in azurerm_role_assignment.role_assignment : key => assignment.id }
}
