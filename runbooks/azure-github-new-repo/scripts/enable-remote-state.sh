#!/bin/bash
# Uncomment the azurerm remote_state block in root.hcl. The scaffolded root.hcl ships this block commented
# out (with a FIXME) so the bootstrap plan/apply can run against local state; now that the storage account
# exists, activate the backend so every unit reads and writes state from Azure Blob Storage.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Ordering guard: enabled only after the client IDs have been recorded.
CLIENT_IDS_DONE="{{ .outputs.capture_client_ids.client_ids_written }}"

cd "$REPO_FILES"

if [ ! -f root.hcl ]; then
  log_error "root.hcl not found at the repository root."
  exit 1
fi

if grep -q '^remote_state {' root.hcl; then
  log_info "remote_state is already active in root.hcl; nothing to do (client IDs recorded: ${CLIENT_IDS_DONE})."
  echo "remote_state_enabled=true" >> "$RUNBOOK_OUTPUT"
  exit 0
fi

log_info "Uncommenting the azurerm remote_state block in root.hcl (client IDs recorded: ${CLIENT_IDS_DONE})..."
# Strip the leading "# " from every line of the commented remote_state block, and drop the stale FIXME
# banner. The range is anchored to the block so the indented inner "#   }" lines and other comments are
# left untouched.
sed -i.bak \
  -e '/^# remote_state {/,/^# }/ s/^# //' \
  -e '/^# FIXME: Uncomment the code below/d' \
  -e '/^#$/d' \
  root.hcl
rm -f root.hcl.bak

if grep -q '^remote_state {' root.hcl; then
  log_info "remote_state is now active in root.hcl."
else
  log_error "Failed to uncomment remote_state in root.hcl. Inspect the file manually."
  exit 1
fi

echo "remote_state_enabled=true" >> "$RUNBOOK_OUTPUT"
exit 0
