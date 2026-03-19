// Environment-level config shared by all units under {{ .AccountName }}/.
// Read by root.hcl via find_in_parent_folders("account.hcl").

locals {
  // S3 bucket for OpenTofu state for this environment.
  state_bucket_name = "{{ .StateBucketName }}"
}
