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

  // A torn google_service_account apply persists `email` and `member` but not `name`, and the
  // default no_merge strategy drops mock_outputs entirely once a dependency yields any output —
  // so `outputs.name` below would fail to parse, taking `run --all` down at init. "shallow" lets
  // real values win and mocks fill only the missing keys. Mocks stay allowed for every command:
  // `run --all apply` reaches this unit before service_account has been applied.
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  service_account_id = dependency.service_account.outputs.name
  member             = values.member
}
