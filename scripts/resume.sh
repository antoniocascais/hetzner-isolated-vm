#!/usr/bin/env bash
# Power the server back on. Idempotent — safe to run against an already-running box.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN
"${ANSIBLE_PLAYBOOK}" "${REPO_ROOT}/ansible/playbooks/resume.yml" "$@"
