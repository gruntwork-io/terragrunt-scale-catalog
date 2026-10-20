include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/gcp/workload-identity-pool-provider"

  update_source_with_cas = true
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  to = google_iam_workload_identity_pool_provider.provider
  id = "projects/$${var.project_id}/locations/global/workloadIdentityPools/$${var.workload_identity_pool_id}/providers/$${var.workload_identity_pool_provider_id}"
}
EOF
}

dependency "workload_identity_pool" {
  config_path = values.workload_identity_pool_config_path

  mock_outputs = {
    workload_identity_pool_id = "mock-pool-id"
  }
}

inputs = {
  project_id                         = values.project_id
  workload_identity_pool_id          = dependency.workload_identity_pool.outputs.workload_identity_pool_id
  workload_identity_pool_provider_id = values.workload_identity_pool_provider_id
  display_name                       = values.display_name

  issuer_uri        = values.issuer_uri
  attribute_mapping = values.attribute_mapping

  description         = try(values.description, null)
  disabled            = try(values.disabled, false)
  attribute_condition = try(values.attribute_condition, null)
  allowed_audiences   = try(values.allowed_audiences, null)
}
