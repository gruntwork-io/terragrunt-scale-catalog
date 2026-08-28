#!/bin/bash
# Activate the azurerm remote_state block in root.hcl. The Azure base root.hcl ships this block commented
# out (with a FIXME) so the first bootstrap apply can run against local state; once the Storage Account
# exists we uncomment it and migrate the state into it.
set -euo pipefail

if [ -z "${REPO_FILES:-}" ]; then
  log_error "No cloned repository found."
  exit 1
fi

ROOT_HCL="$REPO_FILES/root.hcl"
if [ ! -f "$ROOT_HCL" ]; then
  log_error "No root.hcl at the repository root. Run the 'Ensure the repository root configuration' step first."
  exit 1
fi

if grep -qE '^remote_state[[:space:]]*\{' "$ROOT_HCL"; then
  log_info "remote_state is already active in root.hcl. Nothing to do."
  exit 0
fi

if ! grep -qE '^#[[:space:]]*remote_state[[:space:]]*\{' "$ROOT_HCL"; then
  log_error "Could not find a commented remote_state block in root.hcl to uncomment."
  exit 1
fi

log_info "Uncommenting the remote_state block in root.hcl..."
# Delete the FIXME comment (the '# FIXME...' line through the following bare '#' line), then strip the
# leading '# ' from every line of the commented remote_state block. The block runs from '# remote_state {'
# to the closing '# }' — inner braces are indented ('#   }') so they are not matched by the range end.
sed -e '/^# FIXME: Uncomment the code below/,/^#$/d' \
    -e '/^# remote_state {/,/^# }/ s/^# \{0,1\}//' \
    "$ROOT_HCL" > "$ROOT_HCL.tmp"
mv "$ROOT_HCL.tmp" "$ROOT_HCL"

log_info "remote_state is now active. root.hcl will use the azurerm backend."
exit 0
