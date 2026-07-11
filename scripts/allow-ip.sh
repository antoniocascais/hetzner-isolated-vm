#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
ansible-playbook "${REPO_ROOT}/ansible/playbooks/allow-ip.yml" "$@"
