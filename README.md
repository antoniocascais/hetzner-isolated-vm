# hetzner-isolated-vm

A disposable Hetzner Cloud VPS for running Claude Code with full permissions,
with inbound SSH **locked to your current public IP**. Built to limit the blast
radius of "what if Claude goes crazy" on the inbound + cloud-account axes.

## Threat model (read this)

A firewall controls **who can reach the box**, not **what the box can do**.
This setup gives you:

- **Inbound: SSH from your IP only, in steady state.** The Hetzner Cloud
  Firewall allows your configured SSH port (`BOX_SSH_PORT`, default **9427**)
  from your current public /32 and denies everything else. The server is
  created passing the firewall by name, so Hetzner attaches it at creation
  — there is no window where the box sits unfiltered. Note the steady-state
  rule is enforced **off-box** at the Hetzner API layer — there is no local
  nftables input chain, so the whitelist survives anything that happens on the
  box itself.
  The /32 is what actually protects you, not the port number: anyone already on
  the whitelisted address can port-scan you in seconds, and anyone else is dropped
  before they reach sshd. If you'd nonetheless rather this public repo not name
  your real port, set `BOX_SSH_PORT` in `.env` (gitignored) — the default above is
  what you get if you don't, so changing the default alone doesn't decouple them.
- **Outbound: unrestricted.** A misbehaving Claude can still make outbound
  connections — exfiltrate, attack other hosts, or burn API spend. Nothing in
  this repo constrains egress today; see RUNBOOK TODO.

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
                                             + data volume (ext4, delete-protected)
make configure ── Hetzner API ──> re-assert firewall from your CURRENT IP
                ── resolves IP + volume device via API ──> waits for SSH, then
                   bootstrap + mount ~/data + install pinned Claude Code
make pause     ── powers the server off (volume and firewall untouched)
make resume    ── powers it back on
make destroy   ── deletes server + firewall. NEVER the volume.
```

No Tailscale, and no manual interactive step to reach the box. (`make destroy` is
the one exception — it deliberately prompts for the box name to confirm.) Inbound
is your-IP-only throughout.

**One firewall object per box.** Its name is derived from `BOX_NAME`, so two boxes
provisioned from this repo never share a firewall — `make destroy` deletes the
firewall unconditionally, and a shared one would strip protection off the other box.

## Prereqs

- `python3` (3.10+) and `make`
- A Hetzner Cloud API token, ideally in a **dedicated project**, **Read & Write**
- A dedicated SSH keypair at `~/.ssh/hetzner-isolated-vm`
- Outbound reachability to `api.ipify.org` (used to detect your public IP)

`make install` builds a local `.venv` from pinned `requirements.txt` (Ansible + the
Hetzner SDK) and installs the Ansible collections. Nothing touches system Python, so
PEP 668 (`externally-managed-environment`) is a non-issue. It runs automatically before
every target that needs it (`create`, `configure`, `allow-ip`, `ssh`, `pause`, `resume`,
`destroy`), or on its own:

```bash
make install
```

**Set `BOX_CONSOLE_PASSWORD`.** It is optional and defaults to unset, but unset means
the Hetzner web console is a dead end. `make allow-ip` only repairs the *firewall*; it
cannot help when sshd itself is broken or listening on an unexpected port. Hashing needs
`passlib`, which is in `requirements.txt` and works on current Python — it vendors its
own SHA-crypt and does not need the stdlib `crypt` module removed in 3.13.

It is worth setting because it is the *convenient* recovery path, not the only one: if
it was unset at create time you can still get in via the **Hetzner Rescue System**,
which needs nothing prepared in advance. That route has one catch worth knowing before
you need it:
a rescue boot puts sshd on port 22, and this repo's firewall opens only `BOX_SSH_PORT`,
so you must add a temporary port-22 firewall rule first. Full procedure under
"Break-glass" in `RUNBOOK.md`.

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
make configure             # re-asserts firewall from your current IP; installs Claude over SSH
```

Then:

```bash
make ssh      # resolves the IP via the API and uses BOX_SSH_PORT
cd ~/data/workspace && claude --dangerously-skip-permissions
```

`make create` prints the box IP. `make destroy` tears it down.

A raw `ssh` needs the port: sshd does not listen on 22 and the firewall does not
open it, so `ssh -i ~/.ssh/hetzner-isolated-vm -p 9427 claude@<box-ip>` — or just
use `make ssh`, which reads `BOX_SSH_PORT` for you.

## If your IP changes

Home IPs are often dynamic. If you get locked out (SSH hangs), run:

```bash
make allow-ip      # re-detects your current IP, updates the firewall via API
```

This works even while locked out — it talks to the Hetzner API, not the box.

## Layout

```
ansible/
  group_vars/all.yml           # box shape + firewall + volume (env-overridable)
  templates/cloud-init.yaml.j2 # first-boot: user, dedicated pubkey, hardened sshd
  roles/firewall/              # hcloud firewall via API; rule = SSH from your /32
  roles/bootstrap/             # idempotent host hardening over SSH
  roles/volume/                # mounts the persistent data volume at ~/data
  roles/claude/                # pinned Node + pinned Claude Code install
  playbooks/{create,configure,allow-ip,destroy,pause,resume}.yml
scripts/                       # thin .env-loading wrappers
```

## Persistent data

`~/data` on the box is a Hetzner Volume, mounted by-id with `nofail`. It is
**delete-protected and never touched by `make destroy`** — that is the point.
Everything outside `~/data` is ephemeral.

Its name comes from `VOLUME_NAME` and is deliberately **not** derived from
`BOX_NAME`: if the box name drifts, a name-derived volume would orphan under the
old name and bill silently forever. Deleting the volume is a manual, deliberate
act via the Hetzner console or CLI.

`make pause` stops compute billing. It is not free — the volume bills by size
regardless of power state, and the Primary IP bills while reserved.

## Pinned toolchain

Node and Claude Code are pinned to exact versions, installed from the official
nodejs.org tarball with an upstream SHA256 check (no `curl | bash`). To bump
either, edit the vars at the top of `ansible/roles/claude/tasks/main.yml`; the
comment there has the one-liner for fetching a new checksum from
`https://nodejs.org/dist/vX.Y.Z/SHASUMS256.txt`.
