#!/bin/bash
# Apply the bootstrap stack. This creates real GCP resources (Workload Identity Pool/provider and the
# plan/apply service accounts) and the GCS state bucket. Review the plan output above before running this.
set -euo pipefail

# Values collected from the form can arrive wrapped in quotes or padded with spaces.
# None of the names, branches, IDs or versions used here may contain either, so every
# form value is normalised once, up front, and referenced through these variables.
rb_unquote() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  # Strip every layer, not just one: a value can reach a script wrapped more than once
  # (e.g. \"\"latest\"\"), and a single pass would leave the inner pair behind.
  while :; do
    case $v in
      \'*\'|\"*\") v=${v#[\'\"]}; v=${v%[\'\"]} ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

RB_GCPProjectID=$(rb_unquote "{{ .inputs.GCPProjectID }}")
RB_out_generate_bootstrap_bootstrap_dir=$(rb_unquote "{{ .outputs.generate_bootstrap.bootstrap_dir }}")

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

cd "$REPO_FILES/${RB_out_generate_bootstrap_bootstrap_dir}"

log_info "Applying the bootstrap stack..."
terragrunt run --all --non-interactive --provider-cache apply

log_info "Bootstrap apply complete. The plan/apply service accounts now exist in project ${RB_GCPProjectID}."
