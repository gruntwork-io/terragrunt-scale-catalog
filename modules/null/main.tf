terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "registry.opentofu.org/hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "message" {
  type    = string
  default = "test"
}

resource "null_resource" "test" {
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = "echo \"${var.message}\""
    environment = {
      message = var.message
    }
  }
}

output "test" {
  value = null_resource.test.id
}
