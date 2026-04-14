// Gruntwork Pipelines repository-wide configuration.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

repository {
  // Commits on this branch trigger `terragrunt apply`. PRs against it trigger `terragrunt plan`.
  // If you change this, also update the branch trigger in your CI workflow file.
  deploy_branch_name = "{{ .DeployBranch }}"

  // Controls whether each push creates a new status comment or updates the existing one in-place.
  // Docs: https://docs.gruntwork.io/2.0/reference/pipelines/configurations-as-code/api#new_comment_per_push
  status_update {
    new_comment_per_push = {{ .NewCommentPerPush }}
  }

  env {
    PIPELINES_FEATURE_EXPERIMENT_IGNORE_UNITS_WITHOUT_ENVIRONMENT = "true"
    PIPELINES_FEATURE_EXPERIMENT_AUTO_UNLOCK_STATE_LOCK           = "true"
  }
}
