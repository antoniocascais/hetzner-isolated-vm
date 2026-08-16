#!/usr/bin/env bash
# Shared helpers: load .env, locate repo root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible/ansible.cfg"

# Toolchain lives in the venv built by `make install`; fall back to PATH.
VENV_DIR="${REPO_ROOT}/.venv"
if [[ -x "${VENV_DIR}/bin/ansible-playbook" ]]; then
  PY="${VENV_DIR}/bin/python"
  ANSIBLE_PLAYBOOK="${VENV_DIR}/bin/ansible-playbook"
  # localhost hcloud tasks run under the venv so its deps resolve. The remote
  # box pins its own interpreter via add_host, which overrides this.
  export ANSIBLE_PYTHON_INTERPRETER="${PY}"
else
  PY="$(command -v python3)"
  ANSIBLE_PLAYBOOK="$(command -v ansible-playbook)"
fi
export PY ANSIBLE_PLAYBOOK

load_dotenv() {
  local f="${REPO_ROOT}/.env"
  [[ -f "$f" ]] || return 0
  local line k v
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
    if [[ $v == '"'*'"' || $v == "'"*"'" ]]; then
      v="${v:1:-1}"                        # quoted: verbatim (may contain '#')
    else
      v="${v%%[[:space:]]#*}"              # strip unquoted ' # inline comment'
      v="${v#"${v%%[![:space:]]*}"}"       # ltrim
      v="${v%"${v##*[![:space:]]}"}"       # rtrim
    fi
    [[ -z "${!k:-}" ]] && export "${k}=${v}"
  done < "$f"
}

require() {
  local var="$1"
  [[ -n "${!var:-}" ]] || { echo "Error: ${var} is required (set it in .env)" >&2; exit 1; }
}

# group_vars/all.yml reads BOX_* from the environment directly.
