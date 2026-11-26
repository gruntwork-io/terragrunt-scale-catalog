variable "principal_id" {
  description = "The object ID of the Entra ID service principal."
  type        = string
}

variable "role_assignments" {
  description = "The roles to assign to the principal, keyed by a name that stays the same when the assignment changes. condition is an Azure ABAC condition; condition_version defaults to 2.0 when condition is set."
  type = map(object({
    scope                = string
    role_definition_name = string
    description          = string
    condition            = optional(string)
    condition_version    = optional(string)
  }))
  default = {}
}

variable "import_existing" {
  description = "Import an assignment that already gives the principal the same role at the same scope, instead of creating another. Reading the scope's role assignments needs Microsoft.Authorization/roleAssignments/read there."
  type        = bool
  default     = true
}
