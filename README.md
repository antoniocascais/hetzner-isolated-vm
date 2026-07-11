# hetzner-isolated-vm

A disposable Hetzner Cloud VPS for running Claude Code with full permissions,
with inbound SSH **locked to your current public IP**. Built to limit the blast
radius of "what if Claude goes crazy" on the inbound + cloud-account axes.

## Threat model (read this)

A firewall controls **who can reach the box**, not **what the box can do**.
This setup gives you:

- **Inbound: SSH from your IP only.** The Hetzner firewall allows TCP/22 from
  your current public /32 and denies everything else. No other public surface.
- **Outbound: unrestricted** (your choice). A misbehaving Claude can still make
  outbound connections — exfiltrate, attack other hosts, or burn API spend.
  If that matters, add Hetzner `direction: out` rules later (see RUNBOOK TODO).

The single highest-value containment is **not** the firewall:

> **Do not put a privileged Hetzner token on this box.** Use a *dedicated
> Hetzner project* with its own API token. Then a rogue Claude can, at worst,
> trash this one box — not delete your production VPS. The `HCLOUD_TOKEN` here
> lives only in your local `.env`, never on the server.

A **dedicated SSH keypair** (`~/.ssh/hetzner-isolated-vm`) is used for this box only,
so it's isolated from your other servers' keys.

## Architecture

```
make create    ── Hetzner API (localhost) ──> creates server (cloud-init: user,
                                               dedicated pubkey, hardened sshd)
                                             + firewall: SSH from YOUR /32 only
make configure ── resolves IP via API ──> SSH in, bootstrap + install Claude Code
                ── Hetzner API ──> re-assert firewall from your CURRENT IP
```

No Tailscale, no manual interactive step. Inbound is your-IP-only throughout.

## Prereqs

- `python3` (3.10+) and `make`
- A Hetzner Cloud API token, ideally in a **dedicated project**, **Read & Write**
- A dedicated SSH keypair at `~/.ssh/hetzner-isolated-vm`
- Outbound reachability to `api.ipify.org` (used to detect your public IP)

`make install` builds a local `.venv` from pinned `requirements.txt` (Ansible + the
Hetzner SDK) and installs the Ansible collections. Nothing touches system Python, so
PEP 668 (`externally-managed-environment`) is a non-issue. It runs automatically before
`create` / `configure` / `destroy`, or on its own:

```bash
make install
```

> **Python 3.13+ note:** the optional console break-glass password is hashed with
> `passlib`, which imports the stdlib `crypt` module removed in Python 3.13. On 3.13+
> that hashing step fails. Leave `BOX_CONSOLE_PASSWORD` unset (default) — lockout
> recovery is handled by `make allow-ip` over the API, so the console password is
> redundant anyway.

## Getting a Hetzner Cloud token

Scope the token to a **dedicated project** so a rogue box can't touch anything else
you run (this is the core of the threat model above).

1. Sign in to the [Hetzner Cloud Console](https://console.hetzner.cloud/).
2. Create a **new project** (project switcher → **+ New project**), e.g. `hetzner-isolated-vm`.
3. Open that project → **Security** → **API Tokens** → **Generate API Token**.
4. Give it a description, set permission to **Read & Write**, and generate.
5. Copy the token now — it's shown **once**. Put it in `.env` as `HCLOUD_TOKEN`.

Tokens are project-scoped; there's no account-wide Cloud token. Lost it? Delete and
regenerate — existing tokens can't be revealed.

## Quick start

```bash
cp .env.example .env       # set HCLOUD_TOKEN at minimum
make create                # creates box + firewall (SSH from your IP)
make configure             # installs Claude over SSH; re-asserts firewall
```

Then:

```bash
ssh -i ~/.ssh/hetzner-isolated-vm claude@<box-ip>
cd ~/workspace && claude --dangerously-skip-permissions
```

`make create` prints the box IP. `make destroy` tears it down.

## If your IP changes

Home IPs are often dynamic. If you get locked out (SSH hangs), run:

```bash
make allow-ip      # re-detects your current IP, updates the firewall via API
```

This works even while locked out — it talks to the Hetzner API, not the box.

## Layout

```
ansible/
  group_vars/all.yml           # box shape + firewall rules (env-overridable)
  templates/cloud-init.yaml.j2 # first-boot: user, dedicated pubkey, hardened sshd
  roles/firewall/              # hcloud firewall via API; rule = SSH from your /32
  roles/bootstrap/             # idempotent host hardening over SSH
  roles/claude/                # Node + Claude Code install
  playbooks/{create,configure,allow-ip,destroy}.yml
scripts/                       # thin .env-loading wrappers
```
