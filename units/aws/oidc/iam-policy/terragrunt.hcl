include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${values.base_url}//modules/aws/iam-policy?ref=${values.ref}"
}

generate "import"  {
  disable = values.import_arn == ""
  path = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
import {
  to = aws_iam_policy.policy
  id = "${values.import_arn}"
}
EOF
}

inputs = {
  name   = values.name
  policy = values.policy

  tags = try(values.tags, {})
}
