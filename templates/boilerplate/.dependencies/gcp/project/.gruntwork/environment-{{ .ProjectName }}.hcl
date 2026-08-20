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
    gcp_oidc {
		  workload_identity_provider_id = "projects/{{ .GCPProjectNumber }}/locations/global/workloadIdentityPools/{{ .OIDCResourcePrefix }}-pool/providers/{{ .OIDCResourcePrefix }}-provider"
		  plan_service_account_email    = "{{ .OIDCResourcePrefix }}-plan@{{ .GCPProjectID }}.iam.gserviceaccount.com"
		  apply_service_account_email   = "{{ .OIDCResourcePrefix }}-apply@{{ .GCPProjectID }}.iam.gserviceaccount.com"
	  }
  }
}
