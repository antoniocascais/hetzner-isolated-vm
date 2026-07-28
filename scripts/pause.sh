#!/usr/bin/env bash
# Power off the server (stop compute billing) without touching the firewall
# or the data volume. Idempotent — safe to run against an already-stopped box.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/pause.yml" "$@"
