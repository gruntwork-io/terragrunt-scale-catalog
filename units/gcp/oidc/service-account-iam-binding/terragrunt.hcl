include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${values.base_url}//modules/gcp/service-account-iam-binding?ref=${values.ref}"
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  to = google_service_account_iam_member.workload_identity_binding
  id = "$${var.service_account_id} roles/iam.workloadIdentityUser $${var.member}"
}
EOF
}

dependency "service_account" {
  config_path = values.service_account_config_path

  mock_outputs = {
    name = "projects/mock-project/serviceAccounts/mock-sa@mock-project.iam.gserviceaccount.com"
  }

  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  service_account_id = dependency.service_account.outputs.name
  member             = values.member
}
