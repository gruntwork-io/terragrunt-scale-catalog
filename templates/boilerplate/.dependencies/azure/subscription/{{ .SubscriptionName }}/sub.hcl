// Subscription-level config shared by all units under {{ .SubscriptionName }}/.
// Read by root.hcl via find_in_parent_folders("sub.hcl"). Azure equivalent of account.hcl.

locals {
  // Azure Blob Storage used for OpenTofu state in this subscription. Created by the bootstrap stack.
  state_resource_group_name    = "{{ .StateResourceGroupName }}"
  state_storage_account_name   = "{{ .StateStorageAccountName }}"
  state_storage_container_name = "{{ .StateStorageContainerName }}"
}
