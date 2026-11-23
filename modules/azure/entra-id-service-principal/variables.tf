variable "client_id" {
  description = "The client ID of the service principal."
  type        = string
}

variable "owners" {
  description = "Object IDs of the users or service principals that own the service principal. An owner can add credentials to it and sign in as it, so the default is none."
  type        = list(string)
  default     = []
}
