# AWS GitLab Pipelines Bootstrap Stack

## Overview

This Terragrunt stack bootstraps AWS infrastructure for GitLab CI with OIDC authentication. It creates all necessary AWS resources to enable secure, keyless authentication from GitLab CI pipelines to your AWS account for [Gruntwork Pipelines](https://www.gruntwork.io/platform/pipelines).

## What This Stack Creates

### OIDC Provider

- IAM OpenID Connect provider for GitLab CI

### Plan Role (Read-Only Operations)

- IAM role for running Terragrunt plans
- Uses `StringLike` condition (allows any branch/tag on a given project to assume the role)
- Default IAM policy for read-only operations (state-only access by default)

### Apply Role (Read-Write Operations)

- IAM role for running Terragrunt applies & destroys
- Uses `StringEquals` condition (only specified branch)
- IAM policy that allows for S3 state bucket access
- Default IAM policy for resource management (state-only access by default)

## Usage

Read the [official Gruntwork Pipelines installation guide](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingnewrepo) for usage instructions.

## Values

### Required

| Name | Description | Example |
|------|-------------|---------|
| `state_bucket_name` | S3 bucket for OpenTofu state | `my-tofu-state` |
| `gitlab_group_name` | GitLab group name | `my-group` |
| `gitlab_project_name` | GitLab project name | `infrastructure` |

### Optional

| Name | Description | Default |
|------|-------------|---------|
| `terragrunt_scale_catalog_url` | URL of this catalog | `github.com/gruntwork-io/terragrunt-scale-catalog` |
| `terragrunt_scale_catalog_ref` | Git ref to use | `main` |
| `oidc_resource_prefix` | Prefix for IAM resources | `pipelines` |
| `gitlab_server_domain` | GitLab server domain | `gitlab.com` |
| `oidc_provider_url` | Full OIDC provider URL | `https://gitlab.com` |
| `client_id_list` | OIDC client IDs | `["https://gitlab.com"]` |
| `deploy_branch` | Branch allowed to apply | `main` |
| `sub_key` | Subject claim key | `gitlab.com:sub` |
| `sub_plan_value` | Subject for plan role (wildcard) | `project_path:GROUP/PROJECT:*` |
| `sub_apply_value` | Subject for apply role (specific) | `project_path:GROUP/PROJECT:ref_type:branch:ref:main` |
| `bootstrap_iam_policy` | Policy profile to load (`default` or `restrictive`) | `default` |
| `plan_iam_policy` | Custom plan policy JSON | See default below |
| `apply_iam_policy` | Custom apply policy JSON | See default below |

### Default IAM Policies

The stack ships with two IAM policy profiles:

- `default` (more permissive): `default_plan_iam_policy.json` and `default_apply_iam_policy.json`
- `restrictive` (S3 state access only): `restrictive_plan_iam_policy.json` and `restrictive_apply_iam_policy.json`

Set `bootstrap_iam_policy = "restrictive"` if you only want S3 state access. Override `plan_iam_policy` or `apply_iam_policy` values to supply custom JSON if needed.

Both policy profiles automatically template the `state_bucket_name`, for example in the restrictive plan policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCreateAndListS3ActionsOnSpecifiedBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetBucketAcl",
        "s3:GetBucketLogging",
        "s3:CreateBucket",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketTagging",
        "s3:PutBucketPolicy",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutBucketAcl",
        "s3:PutBucketLogging",
        "s3:GetEncryptionConfiguration",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutLifecycleConfiguration",
        "s3:PutBucketOwnershipControls"
      ],
      "Resource": "arn:aws:s3:::YOUR-STATE-BUCKET"
    },
    {
      "Sid": "AllowGetAndPutS3ActionsOnSpecifiedBucketPath",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::YOUR-STATE-BUCKET/*"
    }
  ]
}
```

**Note**: The `default` profile grants broad access suitable for bootstrapping infrastructure. Carefully review and scope these permissions before enabling in production.

## GitLab Subject Claim Formats

### Any Branch or Tag

```text
project_path:my-group/my-project:*
```

### Specific Branch

```text
project_path:my-group/my-project:ref_type:branch:ref:main
```

## Security Considerations

### Branch Protection

The apply role is restricted to the `deploy_branch` (default: `main`). Ensure you have protected branch rules:

- Require merge request approvals
- Require that status checks pass
- Restrict who can push

### Least Privilege

The default policies only grant S3 state access.

Only add the permissions you need, and only on the resources each role needs to access (read-only for plan, read-write for apply).

## Stack Architecture

```mermaid
flowchart TD
    A[GitLab CI Pipeline] -->|1. Request OIDC token| B[GitLab]
    B -->|2. Issue JWT with sub, aud claims| A
    A -->|3. Call AWS STS with token| C[IAM OIDC Provider]

    subgraph AWS["AWS Account"]
        C[IAM OIDC Provider<br/>gitlab.com or self-managed<br/>Validates token signature]
        C -->|Token validated| D[Plan Role]
        C -->|Token validated| E[Apply Role]

        D[Plan Role - Any Branch<br/>StringLike: project_path:group/project:*<br/>Read-only + S3 state access]
        E[Apply Role - Main Branch Only<br/>StringEquals: project_path:group/project:ref_type:branch:ref:main<br/>Write access + S3 state access]

        D --> F[S3 State Bucket]
        E --> F[S3 State Bucket]
        F[S3 State Bucket<br/>OpenTofu state files]
    end
```

## Outputs

| Name | Description |
|------|-------------|
| apply_iam_policy.arn | ARN of the IAM policy for apply role |
| apply_iam_role.arn | ARN of the IAM role for apply operations |
| apply_iam_role.name | Name of the IAM role for apply operations |
| oidc_provider.arn | ARN of the GitLab CI OIDC provider |
| plan_iam_policy.arn | ARN of the IAM policy for plan role |
| plan_iam_role.arn | ARN of the IAM role for plan operations |
| plan_iam_role.name | Name of the IAM role for plan operations |

## Related Documentation

- [GitLab CI/CD with AWS](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
