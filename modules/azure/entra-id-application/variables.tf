variable "display_name" {
  description = "The display name for the Entra ID application."
  type        = string
}

variable "description" {
  description = "The description for the Entra ID application."
  type        = string
}

variable "owners" {
  description = "Object IDs of the users or service principals that own the application. An owner can add credentials to the application and sign in as it, so the default is none."
  type        = list(string)
  default     = []
}
