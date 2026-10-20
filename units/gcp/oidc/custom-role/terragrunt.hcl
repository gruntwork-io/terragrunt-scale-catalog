include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/gcp/custom-role"

  update_source_with_cas = true
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  to = google_project_iam_custom_role.role
  id = "projects/$${var.project_id}/roles/$${var.role_id}"
}
EOF
}

inputs = {
  project_id  = values.project_id
  role_id     = values.role_id
  title       = values.title
  description = try(values.description, "")
  permissions = values.permissions
}
