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
ssh -i ~/.ssh/hetzner-isolated-vm claude@<box-ip>
export ANTHROPIC_API_KEY=...        # or ANTHROPIC_BASE_URL for the Etna gateway
cd ~/workspace
claude --dangerously-skip-permissions
```

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

## Cleanup of obsolete files (one-time)

The earlier Tailscale-based plan left two stale files. Remove them:

```bash
rm -f ansible/playbooks/lockdown.yml scripts/lockdown.sh
```
