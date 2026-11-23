# Entra ID Application Module

## Overview

This OpenTofu module creates a Microsoft Entra ID (formerly Azure Active Directory) application. Entra ID applications are used to establish identity and access management for services and users. When combined with federated identity credentials, they enable OIDC-based authentication for CI/CD pipelines.

The application has the owners in `owners`, and none by default. An owner can add credentials to the application and sign in as it, so a plan shows an owner someone added outside OpenTofu as a change to remove.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| display_name | The display name for the Entra ID application | `string` | n/a | yes |
| description | The description for the Entra ID application | `string` | n/a | yes |
| owners | Object IDs of the users or service principals that own the application | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The object ID of the Entra ID application |
| client_id | The client ID (application ID) of the application |
| display_name | The display name of the application |

## Related Resources

- [Entra ID Service Principal Module](../entra-id-service-principal/) - Create service principal for this application
- [Entra ID Federated Identity Credential Module](../entra-id-federated-identity-credential/) - Add OIDC authentication
- [Entra ID Flexible Federated Identity Credential Module](../entra-id-flexible-federated-identity-credential/) - Add OIDC with claim matching

## References

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/en-us/entra/identity/)
- [Application Registration](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [GitHub Actions with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure)
