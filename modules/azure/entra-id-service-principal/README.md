# Entra ID Service Principal Module

## Overview

This OpenTofu module creates a service principal for an Entra ID application. A service principal is the local representation of an application in a specific Azure tenant. It's what you assign Azure RBAC roles and permissions to, enabling the application to access Azure resources.

The principal that creates the service principal becomes its owner. The module ignores later changes to `owners`, so a plan run by a different principal, such as a Gruntwork Pipelines identity, does not try to change them.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| client_id | The client ID (application ID) of the application | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| object_id | The object ID of the service principal (used for role assignments) |
| display_name | The display name of the application associated with this service principal |

## Related Resources

- [Entra ID Application Module](../entra-id-application/) - Create the application first
- [Entra ID Role Assignment Module](../entra-id-role-assignment/) - Assign roles to this service principal
- [Entra ID App Role Assignment Module](../entra-id-app-role-assignment/) - Grant Microsoft Graph application permissions to this service principal
- [Entra ID Federated Identity Credential Module](../entra-id-federated-identity-credential/) - Add OIDC authentication

## References

- [Service Principals Documentation](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals)
- [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
- [Service Principal Best Practices](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal)
