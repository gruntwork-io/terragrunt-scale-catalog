include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/gcp/service-account"

  update_source_with_cas = true
}

generate "import" {
  disable   = values.import_existing ? false : true
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
import {
  to = google_service_account.service_account
  id = "projects/$${var.project_id}/serviceAccounts/$${var.account_id}@$${var.project_id}.iam.gserviceaccount.com"
}
EOF
}

inputs = {
  project_id   = values.project_id
  account_id   = values.account_id
  display_name = values.display_name

  description = try(values.description, null)
  disabled    = try(values.disabled, false)
}
