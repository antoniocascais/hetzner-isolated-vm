#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/allow-ip.yml" "$@"
