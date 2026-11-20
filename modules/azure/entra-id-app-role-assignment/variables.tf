variable "principal_object_id" {
  description = "The object ID of the service principal that receives the app roles."
  type        = string
}

variable "app_roles" {
  description = "The values of the application permissions (app roles) to assign, such as Application.Read.All. An empty list assigns none."
  type        = list(string)
}

variable "resource_client_id" {
  description = "The client ID of the API that defines the app roles. Defaults to Microsoft Graph."
  type        = string
  default     = "00000003-0000-0000-c000-000000000000"
}
