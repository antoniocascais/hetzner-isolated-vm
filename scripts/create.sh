#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
export BOX_SSH_PUBKEY_FILE="${BOX_SSH_PUBKEY_FILE:-~/.ssh/hetzner-isolated-vm.pub}"

if ! "${PY}" -c "import passlib" 2>/dev/null; then
  echo "Error: passlib missing. Run 'make install' to build the venv." >&2
  exit 1
fi

"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/create.yml" "$@"
