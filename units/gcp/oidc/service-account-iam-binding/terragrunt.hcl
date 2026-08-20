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

  // Mocks are deliberately allowed for every command (no mock_outputs_allowed_terraform_commands):
  // `run --all apply` reaches this unit while its service_account dependency has not been applied
  // yet, so restricting mocks to non-apply commands makes a fresh stack unparseable at apply time.
  //
  // "shallow" is needed on top of that because a google_service_account apply that dies mid-flight
  // persists a partial output set: `email` and `member` are known at plan time and get written,
  // while `id`, `name` and `unique_id` stay "(known after apply)" and never resolve. State then
  // exists but has no `name`, and Terragrunt's default strategy (no_merge) drops mock_outputs
  // entirely as soon as a dependency yields any output at all — so `outputs.name` below fails to
  // parse with "This object does not have an attribute named name", taking the whole `run --all`
  // down at init rather than at apply. "shallow" merges the mocks under the real outputs: real
  // values always win, mocks only fill keys a torn apply left behind, and the next apply replaces
  // them with the truth.
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  service_account_id = dependency.service_account.outputs.name
  member             = values.member
}
