# Entra ID App Role Assignment Module

## Overview

This OpenTofu module grants application permissions (app roles) of an API, Microsoft Graph by default, to a service principal. Assigning an app role to a service principal is how an administrator consents to an application permission, such as `Application.Read.All`.

Granting Microsoft Graph application permissions requires the **Privileged Role Administrator** or **Global Administrator** directory role.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| principal_object_id | The object ID of the service principal that receives the app roles | `string` | n/a | yes |
| app_roles | The values of the app roles to assign, such as `Application.Read.All`. An empty list assigns none | `list(string)` | n/a | yes |
| resource_client_id | The client ID of the API that defines the app roles | `string` | `00000003-0000-0000-c000-000000000000` (Microsoft Graph) | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | The IDs of the app role assignments, keyed by app role value |

## Related Resources

- [Entra ID Service Principal Module](../entra-id-service-principal/) - Create the service principal that receives the app roles

## References

- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Grant an appRoleAssignment to a service principal](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments)
