#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN

NAME="${BOX_NAME:-hetzner-isolated-vm}"
read -r -p "Delete server AND firewall '${NAME}'? Type the name to confirm: " ans
[[ "$ans" == "$NAME" ]] || { echo "Aborted."; exit 1; }

"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/destroy.yml" "$@"
