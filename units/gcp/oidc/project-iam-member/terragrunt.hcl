include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/gcp/project-iam-member"

  update_source_with_cas = true
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  for_each = toset(var.roles)
  to       = google_project_iam_member.bindings[each.value]
  id       = "$${var.project_id} $${each.value} $${var.member}"
}
EOF
}

dependency "service_account" {
  config_path = values.service_account_config_path

  mock_outputs = {
    member = "serviceAccount:mock-sa@mock-project.iam.gserviceaccount.com"
  }
}

inputs = {
  project_id = values.project_id
  member     = dependency.service_account.outputs.member
  roles      = values.roles
}
