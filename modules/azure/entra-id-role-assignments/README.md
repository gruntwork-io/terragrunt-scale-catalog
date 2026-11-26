# Entra ID Role Assignments Module

## Overview

This OpenTofu module gives one principal several Azure RBAC roles, each at its own scope, optionally with an [Azure ABAC condition](https://learn.microsoft.com/en-us/azure/role-based-access-control/conditions-overview).

It imports an assignment that already gives the principal the same role at the same scope, such as one made with the Azure CLI, instead of creating a second one. The first plan shows the import, and later plans show no change. Set `import_existing = false` to skip that lookup.

Import blocks only work in a root module, so use this module from a Terragrunt unit, not from another module.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| principal_id | The object ID of the principal | `string` | n/a | yes |
| role_assignments | The roles to assign, keyed by a name that stays the same when the assignment changes. Each has `scope`, `role_definition_name` and `description`, and optionally `condition` and `condition_version` (2.0 by default when `condition` is set) | `map(object)` | `{}` | no |
| import_existing | Import an assignment that already gives the principal the same role at the same scope. Needs `Microsoft.Authorization/roleAssignments/read` at each scope | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| role_assignment_ids | The IDs of the role assignments, keyed like `role_assignments` |

## Related Resources

- [Entra ID Role Assignment Module](../entra-id-role-assignment/) - One role at one scope

## References

- [Azure RBAC Documentation](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
- [Delegate Azure role assignment management with conditions](https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-overview)
