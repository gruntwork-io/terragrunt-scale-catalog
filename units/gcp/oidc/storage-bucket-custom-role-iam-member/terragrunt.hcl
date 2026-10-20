include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/gcp/storage-bucket-iam-member"

  update_source_with_cas = true
}

dependency "service_account" {
  config_path = values.service_account_config_path

  mock_outputs = {
    member = "serviceAccount:mock-sa@mock-project.iam.gserviceaccount.com"
  }
}

dependency "custom_role" {
  config_path = values.custom_role_config_path

  mock_outputs = {
    role_name = "projects/mock-project/roles/mockRole"
  }
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  for_each = toset(var.roles)
  to       = google_storage_bucket_iam_member.bindings[each.value]
  id       = "$${var.bucket} $${each.value} $${var.member}"
}
EOF
}

inputs = {
  bucket = values.bucket
  member = dependency.service_account.outputs.member
  roles  = [dependency.custom_role.outputs.role_name]
}
