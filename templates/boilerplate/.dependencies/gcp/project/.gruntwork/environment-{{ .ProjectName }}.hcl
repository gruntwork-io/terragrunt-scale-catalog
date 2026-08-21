// Pipelines environment config for the {{ .ProjectName }} GCP account.
// Pipelines reads all .hcl files in .gruntwork/. Add a new file here to register a new environment.
// Docs: https://docs.gruntwork.io/2.0/docs/pipelines/configuration/settings

environment "{{ .ProjectName }}" {
  // Defines the environment as matching all units under {{ .ProjectName }}/.
  filter {
    paths = ["{{ .ProjectName }}/*"]
  }

  authentication {
    // Pipelines authenticates via GCP Federated Workload Identity Provider (OIDC). No static credentials are needed.
    // plan service account: read-only, used on MRs. apply service account: write, used on merge to deploy branch.
    // Both Service Accounts are created by the bootstrap stack in bootstrap/.
    //
    // These three values are single references, never compositions. Each identity string is derived
    // once in this template's boilerplate.yml so that this file cannot drift from what the bootstrap
    // stack actually creates. Do not rebuild them from OIDCResourcePrefix, ProjectName or the pool
    // IDs here -- that is exactly how both previous drift bugs were introduced.
    gcp_oidc {
      workload_identity_provider_id = "{{ .WorkloadIdentityProviderResourceID }}"
      plan_service_account_email    = "{{ .PlanServiceAccountEmail }}"
      apply_service_account_email   = "{{ .ApplyServiceAccountEmail }}"
    }
  }
}
