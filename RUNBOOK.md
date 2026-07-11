# RUNBOOK — hetzner-isolated-vm

## Provision (first time)

```bash
cp .env.example .env          # set HCLOUD_TOKEN (dedicated project!)
make create                   # server + firewall (SSH from your current IP)
make configure                # bootstrap + Claude over SSH; re-assert firewall
```

`make create` prints the box's public IP. `make configure` resolves it
automatically via the API — no manual IP entry.

Verify: `ssh -i ~/.ssh/hetzner-isolated-vm claude@<box-ip>` works; the same from any
other network should be refused.

## Run Claude

```bash
make ssh                            # resolves the IP via API, honors BOX_SSH_PORT
export ANTHROPIC_API_KEY=...        # or ANTHROPIC_BASE_URL for the Etna gateway
cd ~/workspace
claude --dangerously-skip-permissions
```

(`make ssh EXTRA='...'` runs a one-off remote command instead of an interactive
shell.)

## Giving Claude git access

The box runs an npm dep tree with full perms, so treat any credential on it as
potentially exfiltratable. **Never place a personal SSH private key or a high-scope
token on it.** Pick a credential by blast radius and revocability:

- **GitHub App installation token** — short-lived (1h) and repo-scoped. Caveat:
  the App **private key (PEM) is the crown jewel** — if it lives on the box, a
  leak mints tokens for *every* installed repo until you rotate it (worse than a
  deploy key). Only keep the PEM on the box if the App is installed on just the
  repo(s) it touches with **Contents: Read/Write only**; otherwise mint tokens
  off-box and inject only the short-lived token.
- **Per-repo deploy key (write)** — one per repo. Leak blast radius = that one
  repo; revoke instantly in the repo's Deploy keys settings ("last used" is a
  free tripwire).
- **Fine-grained PAT** — specific repos, `contents:write` only, short expiry,
  rotated.

Whatever you choose: push to a **dedicated fork/branch you review**, not upstream
`main`, so abuse of an on-box credential can't land code anywhere that matters.
For unattended use (a bot with no human in the loop) a credential must live on the
box, so lean on the most scoped + revocable option and rotate it between runs.

The crown jewel stays safe regardless: **`HCLOUD_TOKEN` never touches the box**, so
a rogue dep can trash the box but not your Hetzner account.

## Day-2

- **IP changed / locked out**: `make allow-ip` (re-detects your IP, updates the
  firewall via the Hetzner API — works even when you can't reach the box).
- **Update Claude / packages**: `make configure` (idempotent).
- **Reach a service Claude started**: it binds on the box, but the firewall only
  allows TCP/22. To reach another port, add a temporary rule for that port from
  your /32 (extend the firewall rule list), or tunnel over SSH:
  `ssh -i ~/.ssh/hetzner-isolated-vm -L 8080:localhost:8080 claude@<box-ip>`.

## Break-glass (locked out, allow-ip not enough)

If SSH still fails after `make allow-ip` (e.g. sshd broken), use the Hetzner web
console (VNC): log in as `claude` with `BOX_CONSOLE_PASSWORD` (set it in
`.env` before `make create`; needs python passlib locally to hash).

## Teardown

```bash
make destroy        # deletes server + firewall; prompts for the name
```

Data on the box is ephemeral by design. Push anything you want to keep to git
before destroying.

## Known gaps / TODO

- [ ] Outbound egress is unrestricted. To contain a rogue Claude's outbound,
      add `direction: out` firewall rules (allow Anthropic API + apt + github,
      deny rest). Tighten carefully — too strict breaks Claude.
- [ ] Dynamic home IP means occasional `make allow-ip`. SSH access only opens
      one /32 at a time (the last detected). Add more CIDRs to the rule if you
      work from several fixed networks.
- [ ] Token scoping (dedicated project) is by convention, not enforced in code.
- [ ] No automated snapshots. Add a snapshot step if you want fast rollback.
