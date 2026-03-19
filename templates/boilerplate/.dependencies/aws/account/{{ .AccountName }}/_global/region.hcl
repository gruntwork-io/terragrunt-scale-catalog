// Region config for units under this directory. Read by root.hcl via find_in_parent_folders("region.hcl").

locals {
  // The _global/ directory holds resources that don't belong to any particular region (IAM, OIDC providers, etc.).
  // This region is used for AWS API calls to manage those resources.
  aws_region = "{{ .AWSRegion }}"
}
