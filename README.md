# Terragrunt Scale Catalog

This is a catalog of free, open-source Infrastructure as Code (IaC) configurations for setting up [Terragrunt Scale](https://terragrunt.gruntwork.io/terragrunt-scale/) customers.

## Overview

The Terragrunt Scale Catalog provides pre-built, production-ready infrastructure components for bootstrapping CI/CD pipelines with OIDC authentication. It supports AWS, Azure, and GCP cloud providers, with integrations for GitHub and GitLab.

## Repository Structure

This repository is organized into three main components:

### Modules (`modules/`)

Reusable OpenTofu modules that define cloud resources. These are the building blocks referenced by units.

- **`modules/aws/`** - AWS-specific OpenTofu modules
  - `iam-oidc-role` - IAM role with OIDC trust policy
  - `iam-openid-connect-provider` - IAM OIDC provider
  - `iam-policy` - IAM policy documents
  - `iam-role-policy-attachment` - Attach policies to IAM roles
  - `s3-bucket` - S3 bucket for testing Terragrunt Scale workflows

- **`modules/azure/`** - Azure-specific OpenTofu modules
  - `entra-id-application` - Entra ID (Azure AD) application
  - `entra-id-service-principal` - Service principal for applications
  - `entra-id-federated-identity-credential` - Federated identity credential (static subject)
  - `entra-id-flexible-federated-identity-credential` - Flexible federated identity credential (with claim matching expressions)
  - `entra-id-role-assignment` - Role assignment to a specific scope
  - `entra-id-role-assignment-to-sub` - Role assignment at subscription level
  - `resource-group` - Azure resource group
  - `storage-account` - Azure storage account
  - `storage-container` - Azure storage container

- **`modules/gcp/`** - GCP-specific OpenTofu modules
  - `custom-role` - Custom IAM role at the project level
  - `project-iam-member` - IAM member binding at the project level
  - `service-account` - GCP service account
  - `service-account-iam-binding` - IAM binding for a service account
  - `storage-bucket` - GCS storage bucket
  - `storage-bucket-iam-member` - IAM member binding for a GCS bucket
  - `workload-identity-pool` - Workload Identity Pool for OIDC federation
  - `workload-identity-pool-provider` - Workload Identity Pool Provider

### Units (`units/`)

Terragrunt unit configurations that wrap modules with specific configurations and dependencies. Units represent deployable infrastructure components.

- **`units/aws/oidc/`** - AWS OIDC configuration units
  - `iam-oidc-role` - Configured IAM OIDC role
  - `iam-openid-connect-provider` - Configured OIDC provider
  - `iam-policy` - Configured IAM policy
  - `iam-role-policy-attachment` - Configured policy attachment

- **`units/azure/state/`** - Azure state management units
  - `resource-group` - Resource group for state storage
  - `storage-account` - Storage account for OpenTofu state
  - `storage-container` - Container for state files

- **`units/azure/oidc/`** - Azure OIDC configuration units
  - `entra-id-application` - Configured Entra ID application
  - `entra-id-service-principal` - Configured service principal
  - `entra-id-federated-identity-credential` - Configured federated identity (static)
  - `entra-id-flexible-federated-identity-credential` - Configured flexible federated identity
  - `service-principal-to-scope-role-assignment` - Role assignment to a specific scope
  - `service-principal-to-sub-role-assignment` - Role assignment at subscription level

- **`units/gcp/oidc/`** - GCP OIDC configuration units
  - `custom-role` - Configured custom IAM role
  - `project-iam-member` - Configured project-level IAM member
  - `service-account` - Configured GCP service account
  - `service-account-iam-binding` - Configured service account IAM binding
  - `storage-bucket-custom-role-iam-member` - Configured custom role IAM binding for a GCS bucket
  - `storage-bucket-iam-member` - Configured IAM member binding for a GCS bucket
  - `workload-identity-pool` - Configured Workload Identity Pool
  - `workload-identity-pool-provider` - Configured Workload Identity Pool Provider

### Stacks (`stacks/`)

Terragrunt stack configurations that compose multiple units into complete infrastructure setups. Stacks represent end-to-end solutions.

- **`stacks/aws/github/pipelines-identity/`** - Bootstrap AWS resources for Gruntwork Pipelines (GitHub Actions) with OIDC
- **`stacks/aws/gitlab/pipelines-identity/`** - Bootstrap AWS resources for Gruntwork Pipelines (GitLab CI) with OIDC
- **`stacks/azure/github/pipelines-identity/`** - Bootstrap Azure resources for Gruntwork Pipelines (GitHub Actions) with OIDC
- **`stacks/azure/gitlab/pipelines-identity/`** - Bootstrap Azure resources for Gruntwork Pipelines (GitLab CI) with OIDC
- **`stacks/gcp/github/pipelines-identity/`** - Bootstrap GCP resources for Gruntwork Pipelines (GitHub Actions) with OIDC
- **`stacks/gcp/gitlab/pipelines-identity/`** - Bootstrap GCP resources for Gruntwork Pipelines (GitLab CI) with OIDC

### Templates (`templates/`)

Templates for quickly scaffolding new Terragrunt Scale infrastructure repositories. These templates provide a standardized starting point for different cloud providers and CI/CD platforms.

#### Boilerplate Templates (`templates/boilerplate/`)

Boilerplate repository templates that include all necessary Terragrunt configurations, dependencies, and structure for bootstrapping Gruntwork Pipelines.

**AWS Templates:**

- **`aws/github/`** - Complete AWS + GitHub Actions setup
  - `account/` - Account-level bootstrap configuration
    - `{{ .AccountName }}/_global/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

- **`aws/gitlab/`** - Complete AWS + GitLab CI setup
  - `account/` - Account-level bootstrap configuration
    - `{{ .AccountName }}/_global/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

**Azure Templates:**

- **`azure/github/`** - Complete Azure + GitHub Actions setup
  - `subscription/` - Subscription-level bootstrap configuration
    - `{{ .SubscriptionName }}/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

- **`azure/gitlab/`** - Complete Azure + GitLab CI setup
  - `subscription/` - Subscription-level bootstrap configuration
    - `{{ .SubscriptionName }}/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

**GCP Templates:**

- **`gcp/github/`** - Complete GCP + GitHub Actions setup
  - `project/` - Project-level bootstrap configuration
    - `{{ .ProjectName }}/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

- **`gcp/gitlab/`** - Complete GCP + GitLab CI setup
  - `project/` - Project-level bootstrap configuration
    - `{{ .ProjectName }}/pipelines-identity/` - pipelines-identity stack configuration
    - `boilerplate.yml` - Template variables and dependencies
  - `infrastructure-live/` - Infrastructure live repository structure
    - `boilerplate.yml` - Repository-level dependencies and configuration

## Documentation

Detailed documentation for each component can be found in their respective directories:

- [Modules Documentation](modules/)
- [Units Documentation](units/)
- [Stacks Documentation](stacks/)
- [Templates Documentation](templates/)

## Use Cases

### Bootstrap Gruntwork Pipelines

Regardless of whether you're using GitHub Actions or GitLab CI with AWS, Azure, or GCP, you can bootstrap Gruntwork Pipelines by following the documentation in the official [Gruntwork Pipelines setup docs](https://docs.gruntwork.io/2.0/docs/pipelines/installation/addingnewrepo).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

See [LICENSE](LICENSE) for full details.
