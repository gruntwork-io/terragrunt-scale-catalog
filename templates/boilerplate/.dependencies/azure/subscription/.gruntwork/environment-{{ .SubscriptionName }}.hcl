// Pipelines environment config for the {{ .SubscriptionName }} Azure subscription.
// Pipelines reads all .hcl files in .gruntwork/. Add a new file here to register a new environment.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

environment "{{ .SubscriptionName }}" {
  // Defines the environment as matching all units under {{ .SubscriptionName }}/.
  filter {
    paths = ["{{ .SubscriptionName }}/*"]
  }

  authentication {
    // Pipelines authenticates via Azure Federated Identity (OIDC). No client secrets are stored.
    // plan client: read-only, used on MRs. apply client: write, used on merge to deploy branch.
    // Both App Registrations are created by the bootstrap stack in bootstrap/.
    azure_oidc {
      tenant_id       = "{{ .AzureTenantID }}"
      subscription_id = "{{ .AzureSubscriptionID }}"

      plan_client_id  = "" # FIXME: Fill in the client ID for the plan application after bootstrapping
      apply_client_id = "" # FIXME: Fill in the client ID for the apply application after bootstrapping
    }
  }
}
