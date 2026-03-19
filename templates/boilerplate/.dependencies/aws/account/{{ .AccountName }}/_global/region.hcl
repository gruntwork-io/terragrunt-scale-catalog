// Region config for units under this directory. Read by root.hcl via find_in_parent_folders("region.hcl").
// To deploy into a new region, create a new <region>/ directory with its own region.hcl.

locals {
  // The _global/ directory holds environment-wide resources (IAM, OIDC providers, etc.).
  // Even global resources need a region for the AWS API — this value serves that purpose.
  aws_region = "{{ .AWSRegion }}"
}
