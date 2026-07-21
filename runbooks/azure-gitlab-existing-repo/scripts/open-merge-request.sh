#!/bin/bash
# Commit the generated configuration, push the setup branch, and open a merge request with glab.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the migrate-state output gates this block until state migration has completed.
: "{{ .outputs.migrate_state.state_migrated }}"

cd "$REPO_FILES"

BRANCH="add-gruntwork-pipelines"
TARGET="{{ .inputs.DeployBranch }}"

log_info "Preparing branch ${BRANCH}..."
git checkout -B "$BRANCH"
git add -A

if git diff --cached --quiet; then
  log_warn "No staged changes to commit; the branch may already be up to date."
else
  git commit -m "Add Gruntwork Pipelines bootstrap for {{ .inputs.SubscriptionName }} [skip ci]"
fi

log_info "Pushing ${BRANCH} to origin..."
git push -u origin "$BRANCH"

log_info "Opening merge request against ${TARGET}..."
glab mr create \
  --source-branch "$BRANCH" \
  --target-branch "$TARGET" \
  --title "Add Gruntwork Pipelines bootstrap for {{ .inputs.SubscriptionName }} [skip ci]" \
  --description "Adds the GitLab CI Pipelines configuration and the {{ .inputs.SubscriptionName }} subscription bootstrap (Entra ID plan/apply applications + federated credentials). Generated with a Gruntwork Runbook." \
  --yes

log_info "Merge request opened. Merging it to ${TARGET} will trigger the first Pipelines apply run."
exit 0
