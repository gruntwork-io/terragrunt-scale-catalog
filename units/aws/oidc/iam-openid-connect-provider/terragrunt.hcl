include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${values.base_url}//modules/aws/iam-openid-connect-provider?ref=${values.ref}"
}

generate "import"  {
  disable = values.import_arn == ""
  path = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
import {
  to = aws_iam_openid_connect_provider.identity_provider
  id = "${values.import_arn}"
}
EOF
}


inputs = {
  url            = values.url
  client_id_list = values.client_id_list

  tags = try(values.tags, {})
}
