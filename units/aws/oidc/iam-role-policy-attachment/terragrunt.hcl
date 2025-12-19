include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${values.base_url}//modules/aws/iam-role-policy-attachment?ref=${values.ref}"
}

dependency "iam_role" {
  config_path = values.iam_role_config_path

  mock_outputs = {
    name = try(values.mock_iam_role_name, "mock-role")
  }
}

dependency "iam_policy" {
  config_path = values.iam_policy_config_path

  mock_outputs = {
    arn = try(values.mock_iam_policy_arn, "arn:aws:iam::123456789012:policy/mock-policy")
  }
}

generate "import"  {
  disable = values.import_arn == ""
  path = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
import {
  to = aws_iam_role_policy_attachment.arn_policy_attachments_for_role
  id = "${values.import_arn}"
}
EOF
}

inputs = {
  role_name  = dependency.iam_role.outputs.name
  policy_arn = dependency.iam_policy.outputs.arn

  tags = try(values.tags, {})
}
