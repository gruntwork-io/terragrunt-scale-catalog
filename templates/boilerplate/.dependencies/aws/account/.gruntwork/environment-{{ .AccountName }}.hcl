// Pipelines environment config for the {{ .AccountName }} AWS account.
// Pipelines reads all .hcl files in .gruntwork/. Add a new file here to register a new environment.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

environment "{{ .AccountName }}" {
  // Defines the environment as matching all units under {{ .AccountName }}/.
  filter {
    paths = ["{{ .AccountName }}/*"]
  }

  authentication {
    // Pipelines assumes these IAM roles via OIDC. No static credentials needed.
    // plan role: read-only, used on PRs. apply role: write, used on merge to deploy branch.
    // Both roles are created by the bootstrap stack in _global/bootstrap/.
    aws_oidc {
      account_id         = "{{ .AWSAccountID }}"
      plan_iam_role_arn  = "arn:{{ .Partition }}:iam::{{ .AWSAccountID }}:role/{{ .OIDCResourcePrefix }}-plan"
      apply_iam_role_arn = "arn:{{ .Partition }}:iam::{{ .AWSAccountID }}:role/{{ .OIDCResourcePrefix }}-apply"
      aws_partition      = "{{ .Partition }}"
    }
  }
}
