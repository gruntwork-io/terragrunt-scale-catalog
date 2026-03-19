// Root Terragrunt config included by every unit via `find_in_parent_folders("root.hcl")`.
// Configures S3 remote state and generates the AWS provider for all units.
// Docs: https://docs.terragrunt.com/reference/config-blocks-and-attributes/#remote_state

// Read environment-level config from the nearest parent files.
locals {
  account_hcl       = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  state_bucket_name = local.account_hcl.locals.state_bucket_name

  region_hcl = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region = local.region_hcl.locals.aws_region
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket       = local.state_bucket_name
    region       = local.aws_region
    key          = "${path_relative_to_include()}/tofu.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

// Generates provider.tf in each unit at plan/apply time.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}
