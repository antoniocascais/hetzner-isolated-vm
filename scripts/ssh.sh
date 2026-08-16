#!/usr/bin/env bash
# Resolve the box IP via the Hetzner API and SSH in. Extra args run as a remote
# command: ./scripts/ssh.sh 'uptime'
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_dotenv
require HCLOUD_TOKEN

ip="$("${PY}" - <<'PY'
import os
from hcloud import Client
name = os.environ.get("BOX_NAME", "hetzner-isolated-vm")
s = Client(token=os.environ["HCLOUD_TOKEN"]).servers.get_by_name(name)
if not s:
    raise SystemExit(f"Server {name!r} not found — run 'make create' first.")
print(s.public_net.ipv4.ip)
PY
)"

key="${BOX_SSH_KEY:-$HOME/.ssh/hetzner-isolated-vm}"
key="${key/#\~/$HOME}"
# Deliberate copy of the TOFU policy (raw ssh doesn't read ansible.cfg).
# Keep in sync with ansible.cfg + bootstrap's probe: docs/decisions.md#ssh-host-key.
exec ssh -i "${key}" -p "${BOX_SSH_PORT:-9427}" \
  -o StrictHostKeyChecking=accept-new \
  "${BOX_USER:-claude}@${ip}" "$@"
