// Region config for units under this directory. Read by root.hcl via find_in_parent_folders("region.hcl").
// To deploy into a new region, create a new <region>/ directory with its own region.hcl.

locals {
  // The _global/ directory holds environment-wide resources (IAM, OIDC providers, etc.).
  // Global resources also need a region for the AWS API.
  aws_region = "{{ .AWSRegion }}"
}
