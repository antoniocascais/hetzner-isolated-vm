#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
export BOX_SSH_PUBKEY_FILE="${BOX_SSH_PUBKEY_FILE:-~/.ssh/hetzner-isolated-vm.pub}"

if ! python3 -c "import passlib" 2>/dev/null; then
  echo "Error: passlib required for password hashing. Install python3-passlib / python-passlib." >&2
  exit 1
fi

ansible-playbook "${REPO_ROOT}/ansible/playbooks/create.yml" "$@"
