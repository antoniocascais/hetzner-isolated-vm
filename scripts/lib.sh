#!/usr/bin/env bash
# Shared helpers: load .env, locate repo root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible/ansible.cfg"

load_dotenv() {
  local f="${REPO_ROOT}/.env"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in ''|\#*) continue ;; esac
    if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
      v="${v%%$'\r'}"
      [[ $v == '"'*'"' ]] && v="${v:1:-1}"
      [[ $v == "'"*"'" ]] && v="${v:1:-1}"
      [[ -z "${!k:-}" ]] && export "${k}=${v}"
    fi
  done < "$f"
}

require() {
  local var="$1"
  [[ -n "${!var:-}" ]] || { echo "Error: ${var} is required (set it in .env)" >&2; exit 1; }
}

# group_vars/all.yml reads BOX_* from the environment directly.
