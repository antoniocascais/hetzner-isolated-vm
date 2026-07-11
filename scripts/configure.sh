#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
# configure.yml resolves the server's public IP via the API and builds its own
# inventory (add_host), so no -i / no tailscale IP needed.
"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/configure.yml" "$@"
