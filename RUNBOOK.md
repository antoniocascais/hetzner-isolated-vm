# RUNBOOK — hetzner-isolated-vm

## Provision (first time)

```bash
cp .env.example .env          # set HCLOUD_TOKEN (dedicated project!)
make create                   # server + firewall (SSH from your current IP)
make configure                # re-assert firewall; bootstrap + Claude over SSH
```

`make create` prints the box's public IP. `make configure` resolves it
automatically via the API — no manual IP entry.

Verify: `make ssh` works; the same from any other network should be refused.

Prefer `make ssh` over a raw `ssh` — it resolves the IP via the API and passes
`-p $BOX_SSH_PORT`. sshd does **not** listen on 22 and the firewall does not open
it, so a bare `ssh user@host` will hang. The raw equivalent is:

```bash
ssh -i ~/.ssh/hetzner-isolated-vm -p 9427 claude@<box-ip>   # -p must match BOX_SSH_PORT
```

## Run Claude

```bash
make ssh                            # resolves the IP via API, honors BOX_SSH_PORT
export ANTHROPIC_API_KEY=...        # or ANTHROPIC_BASE_URL for a proxied gateway
cd ~/data/workspace
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
  allows your configured SSH port (`BOX_SSH_PORT`). To reach another port, add a temporary rule for that port from
  your /32 (extend the firewall rule list), or tunnel over SSH:
  `ssh -i ~/.ssh/hetzner-isolated-vm -p 9427 -L 8080:localhost:8080 claude@<box-ip>`
  (or `make ssh EXTRA='-L 8080:localhost:8080'`, which fills in the port for you).
- **"REMOTE HOST IDENTIFICATION HAS CHANGED" after `make destroy` + `make create`**:
  expected, not a MITM alarm — a rebuilt box is a fresh install with a fresh SSH
  host key, and `StrictHostKeyChecking=accept-new` (set in `ansible/ansible.cfg`
  for Ansible's connections and `scripts/ssh.sh` for `make ssh`) correctly
  hard-fails the moment a *known* host's key changes rather than silently trusting
  it. Remove just the stale `known_hosts` entry (`ssh-keygen -R <ip-or-host>`) and
  reconnect — the new key is trusted on that next first connection. **Do not** set
  `StrictHostKeyChecking=no` to work around this; that disables the exact check
  that's protecting you. (Whether a rebuilt box reuses its previous IP often enough
  for this to bite is unverified — this is what to do *if* it happens.)

## Break-glass (locked out, allow-ip not enough)

Two mechanisms exist. **Start with Rescue** — it needs nothing prepared before
`make create` (not yet walked end to end; see below). The web console is faster, but
only works if `BOX_CONSOLE_PASSWORD` was set before create — if you didn't set it,
or aren't sure, go straight to Rescue.

### Hetzner Rescue System (no advance setup required)

Hetzner can boot the server into a rescue Linux and hand you a fresh root password,
optionally injecting your SSH key, **regardless of whether `BOX_CONSOLE_PASSWORD` was
ever set.** The server's disk is untouched — you mount it and fix whatever you broke.

**The catch nobody hits until they need it: the rescue system's sshd listens on port
22, and our Cloud Firewall only opens `BOX_SSH_PORT`.** So rescue boots fine and you
still can't reach it. The firewall is Hetzner-side and editable from the web console
without touching the box, so the fix is a temporary rule — but you have to know to add
it.

1. Hetzner Cloud Console → the server → **Rescue** → enable (type `linux64`), selecting
   your SSH key if offered. Save the root password it shows you; it is displayed once.
2. **Before rebooting**, add a temporary inbound rule to the firewall: TCP **22** from
   your current IP. (Detaching the firewall entirely also works and is faster under
   pressure, but leaves the box fully exposed until you re-attach it — prefer the rule.)
3. Reboot the server (Power → Reset). It comes up in rescue.
4. `ssh -p 22 root@<box-ip>`, then mount the system disk and repair — typically
   `mount /dev/sda1 /mnt` and edit `/mnt/etc/ssh/sshd_config`.
5. Disable Rescue in the console, reboot back into the normal system, confirm SSH works
   on `BOX_SSH_PORT`, then **remove the temporary port-22 rule**.

`make allow-ip` is safe to run at any point during this, including while the temporary
port-22 rule is in place — it won't touch or remove that rule until the box actually
answers on `BOX_SSH_PORT` again, and if you added the rule wide-open under pressure,
`allow-ip` automatically narrows it to your detected /32 rather than leaving it exposed.

**Not verified end to end.** Nothing here drives Rescue via code — the procedure above
is manual console clicks, and `enable_rescue` appears nowhere in this repo's own
`ansible/`, `scripts/`, or `Makefile` sources. The SDK having the method elsewhere is
not evidence for a procedure that's entirely manual. The port-22 firewall interaction
is inferred from our own firewall rules (`create.yml` opens only `BOX_SSH_PORT`), not
from a rescue boot anyone has actually performed here. Walk it once on a throwaway box
before you need it.

### Hetzner web console / VNC (faster, but only if you prepared for it)

If SSH still fails after `make allow-ip` (e.g. sshd broken, or listening on a port
the firewall no longer allows), and you did set `BOX_CONSOLE_PASSWORD`, use the
Hetzner web console (VNC): log in as `claude` with `BOX_CONSOLE_PASSWORD`.

This only works if you set `BOX_CONSOLE_PASSWORD` in `.env` **before `make create`** —
it is baked in by cloud-init at first boot and cannot be added to a running box from
here. If it was unset at create time, the console shows a login prompt you have no
credentials for — in that case this path is a dead end and you want Rescue above, not
this one. Verify you can actually log in via the console once, while SSH still works —
an untested break-glass is not a break-glass.

Only if neither of the above gets you back in is `make destroy` + `make create` the
answer (which preserves `~/data`, but nothing else).

**`ssh.socket` is masked during bootstrap.** On Ubuntu 26.04 socket activation can
override `sshd_config`'s `Port`, so a config saying 9427 may not be what actually
listens. If someone re-enables `ssh.socket` while debugging, that footgun comes
back — leave it masked and use `ssh.service`.

## Teardown

```bash
make destroy        # deletes server + firewall; prompts for the name
```

**`make destroy` never deletes the data volume.** `~/data` survives teardown and
is reattached by the next `make create`. Everything *outside* `~/data` is
ephemeral — push anything else you want to keep to git before destroying.

To actually delete the volume and its data, do it deliberately via the Hetzner
console or `hcloud` CLI. It carries `delete_protection: true`, so you must clear
that first. No playbook will ever do this for you.

## Pause / resume

```bash
make pause          # powers the server off; volume + firewall untouched
make resume         # powers it back on
```

Both are idempotent. **Paused is probably not free**: per Hetzner's published pricing
(not verified against an actual invoice from this repo), the volume bills by size
whatever the power state, and the Primary IP bills while reserved. `pause` only stops
compute billing — check the Hetzner Cloud Console if you need to confirm the rest.

`resume` re-checks that the volume is still attached to this box. The warning it
prints splits into two genuinely different cases — read which one you got before
doing anything:

- **Attached to a different server.** Your data is intact — do **not** assume data
  loss and do **not** format anything. But `make create` will not just quietly
  reattach it: `ansible/playbooks/create.yml` refuses to attach a volume that's
  attached elsewhere unless `VOLUME_ALLOW_REATTACH=true` is set, and only after
  the other server is stopped (`make pause`, run from an environment pointed at
  *that* box — a live filesystem can't be safely pulled out from under a running
  machine). So: pause the other box, set `VOLUME_ALLOW_REATTACH=true` (shell or
  `.env`), run `make create` (reattaches, does **not** reformat), then
  `make configure`, then unset `VOLUME_ALLOW_REATTACH` again — it's a one-time
  confirmation, not a standing setting. See `.env.example` for the full rationale.
- **Gone entirely.** This is not a reattach — the data itself is gone unless you
  have an external backup. `make create` in this case provisions a brand-new,
  *empty* volume under the same name; it is not a restore. There is nothing else
  this repo can do to recover the old contents.

## Bumping Node / Claude Code

Both are pinned. Edit the vars at the top of `ansible/roles/claude/tasks/main.yml`:
Node needs a matching SHA256 from `https://nodejs.org/dist/vX.Y.Z/SHASUMS256.txt`;
Claude Code needs only the version. Re-provisioning purges any older
NodeSource-installed `nodejs` package so the box converges on the pinned tarball.

**The two bumps are not independent.** npm's global prefix lives under the
version-specific Node install root, so bumping Node deletes the installed Claude
Code along with the old root and reinstalls it against the new prefix. A Node-only
bump therefore still needs `registry.npmjs.org` reachable — which will matter once
egress is locked down.

## Known gaps / TODO

- [ ] **Outbound egress is unrestricted by this repo.** A working nftables
      default-deny egress tool (`claude-fw`) was hand-built on the live box and is
      captured but **not yet provisioned by Ansible** — a rebuilt box has no egress
      containment. Porting it is the next phase. Until then, do not describe a box
      built from this repo as egress-contained.
- [ ] No local inbound filtering. Inbound whitelisting is entirely the Hetzner
      Cloud Firewall (off-box); there is no nftables input chain.
- [ ] Dynamic home IP means occasional `make allow-ip`. SSH access only opens
      one /32 at a time (the last detected). Add more CIDRs to the rule if you
      work from several fixed networks.
- [ ] Token scoping (dedicated project) is by convention, not enforced in code.
- [ ] No automated snapshots. Add a snapshot step if you want fast rollback.
- [ ] **The SSH port-transition path has never run against a real sshd restart.**
      Changing `BOX_SSH_PORT` on an existing box triggers a sequence — `allow-ip`
      keeps the old firewall rule open until the new port answers, `configure`
      connects on whichever port works, bootstrap moves sshd, then Ansible
      re-points its own connection mid-play and drops the multiplexed socket.
      Every piece is verified in isolation, and the logic traces correctly end to
      end. What has **not** happened is a real run where sshd actually restarts
      underneath a live Ansible connection. That is the one thing that can't be
      proven without infrastructure. **Do a throwaway-box dry run before changing
      `BOX_SSH_PORT` on a box you care about**, and read the Rescue System section
      above first — this is precisely the failure it exists for.
- [ ] **`~/.claude/CLAUDE.md` on the box does not converge.** The `claude` role
      templates it with `force: false` (`ansible/roles/claude/tasks/main.yml`), and
      `configure.yml` includes that role on every run — so the first `make configure`
      writes the file, and every one after that leaves an existing copy untouched.
      Deliberate: it protects on-box edits from being clobbered. But it also means a
      template change here never reaches a box that already has the file. To pick one
      up, delete `~/.claude/CLAUDE.md` on the box and re-run `make configure`.
- [ ] **This repo does not converge a box created before the data volume existed.**
      `configure.yml` asserts the volume exists and is attached, and aborts if not,
      so `make configure` will not run against such a box. This is deliberate: the
      alternative is an optional-volume code path, which is how state quietly ends
      up on the ephemeral disk. Rebuild instead — `make destroy` + `make create`
      provisions the volume, and `~/data` survives from then on.
