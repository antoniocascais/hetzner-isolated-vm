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

- `ansible`, `ansible-galaxy`
- A Hetzner Cloud API token (ideally in a dedicated project, Read & Write)
- Python `passlib` *only if* you set a console break-glass password
- (keypair `~/.ssh/hetzner-isolated-vm` already created)

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
