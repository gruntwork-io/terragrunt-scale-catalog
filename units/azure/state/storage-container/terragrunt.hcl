include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../..//modules/azure/storage-container"

  update_source_with_cas = true
}

dependency "storage_account" {
  config_path = values.storage_account_config_path

  mock_outputs = {
    id = "/subscriptions/12345678-9123-4567-8901-234567890123/resourceGroups/mockrg/providers/Microsoft.Storage/storageAccounts/mockname"
  }
}

inputs = {
  name = values.name

  storage_account_id = dependency.storage_account.outputs.id
}
