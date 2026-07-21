#!/bin/bash
# Configure Application Default Credentials for GCP. Terragrunt and OpenTofu use these to
# authenticate when planning and applying the bootstrap stack. This opens a browser to complete
# the Google login flow.
set -euo pipefail

log_info "Launching Google Cloud application-default login. A browser window will open."
log_info "Sign in and select the GCP project you intend to bootstrap Pipelines in."
gcloud auth application-default login

log_info "Application Default Credentials configured. Terragrunt/OpenTofu will use these to authenticate to GCP."
exit 0
