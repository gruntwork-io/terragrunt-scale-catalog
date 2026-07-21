#!/bin/bash
# Uncomment the azurerm remote_state block in root.hcl now that the state storage account exists.
# Idempotent: if the block is already active (or absent), this is a no-op.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found. Complete the earlier steps first."
  exit 1
fi

# Referencing the capture output gates this block until the client IDs have been captured.
: "{{ .outputs.capture_client_ids.plan_client_id }}"

ROOT_HCL="$REPO_FILES/root.hcl"

if [ ! -f "$ROOT_HCL" ]; then
  log_error "root.hcl not found at the repository root."
  exit 1
fi

if grep -Eq '^[[:space:]]*remote_state[[:space:]]*\{' "$ROOT_HCL"; then
  log_info "root.hcl already has an active remote_state block; nothing to uncomment."
  echo "remote_state_enabled=true" >> "$RUNBOOK_OUTPUT"
  exit 0
fi

if ! grep -Eq '^#[[:space:]]*remote_state[[:space:]]*\{' "$ROOT_HCL"; then
  log_warn "No commented remote_state block found in root.hcl; assuming the backend is already configured."
  echo "remote_state_enabled=true" >> "$RUNBOOK_OUTPUT"
  exit 0
fi

log_info "Uncommenting the azurerm remote_state block in root.hcl..."
awk '
  /^# remote_state \{/ { inblock = 1 }
  inblock {
    line = $0
    sub(/^# ?/, "", line)
    print line
    if ($0 ~ /^# \}$/) { inblock = 0 }
    next
  }
  { print }
' "$ROOT_HCL" > "${ROOT_HCL}.tmp"
mv "${ROOT_HCL}.tmp" "$ROOT_HCL"

echo "remote_state_enabled=true" >> "$RUNBOOK_OUTPUT"
log_info "Enabled the azurerm remote-state backend in root.hcl."
exit 0
