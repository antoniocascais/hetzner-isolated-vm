# Design decisions and the proofs behind them

This file is the canonical home for the *why* behind a few deliberately
guarded choices in this repo. Each section states the rule that is actually
enforced in the code and the proof it was verified against, so the code
itself only has to carry a short pointer instead of the full essay. Do not
**weaken any rule while reading here**: if a section says "do NOT reorder" or
"do NOT re-add a value", that warning still lives in the code and wins.

Versions in use: ansible-core **2.21.1** (the `.venv` built by `make
install`), hetzner.hcloud **6.10.0** (vendored under
`ansible/collections/`), ansible.posix **2.2.1**, community.general
**13.1.0**.

---

## SSH host key

**Rule enforced in `ansible/ansible.cfg`:**
`host_key_checking = True`, and the single canonical `ssh_args` set for every
ssh connection. Do NOT flip `host_key_checking` to False and do NOT re-add a
per-play/per-host `ansible_ssh_common_args` override with a different value.

**Proof (verified against ansible-core 2.21.1).** This repo sets the TOFU
policy via `ssh_args = -o ... -o StrictHostKeyChecking=accept-new`. Two
things could quietly break that policy, and both were disproven by reading
`.venv/lib/python*/site-packages/ansible/plugins/connection/ssh.py`:

1. **`host_key_checking = False` would not break accept-new, but is still
   wrong.** ssh_args is appended at ssh.py **L839-844**. The
   `-o StrictHostKeyChecking=no` that `host_key_checking=False` injects is
   appended *after* that, at **L847-849**. OpenSSH takes the FIRST value it
   sees for a repeated `-o` option (confirmed: `ssh -F /dev/null -o
   StrictHostKeyChecking=accept-new -o StrictHostKeyChecking=no -G host`
   resolves to accept-new; reversed order resolves to no). Confirmed
   end-to-end with `ANSIBLE_HOST_KEY_CHECKING=False` and `-vvvv` against an
   unroutable probe host: both flags appear on the real command line,
   accept-new first. So `True` vs `False` wouldn't change the working
   accept-new outcome today. `True` is kept anyway because
   `host_key_checking` is read **again at ssh.py:1374**, in the password-auth failure path, where it upgrades a bare "Host key
   verification failed" into a fingerprint hint — not live here (key-auth
   only) but the correct posture with no footgun for a future password path.

2. **`ansible_ssh_common_args` is additive, not a replacement.** ssh_args is
   appended at L839-844; the internal option that
   `ansible_ssh_common_args` feeds is appended separately, later, at
   **L895-899** (the actual append call is line **899**) — both onto the same
   command, neither replacing the other. Confirmed at **L1594-1597**, where
   `_is_tty_requested` walks `('ssh_args', 'ssh_common_args',
   'ssh_extra_args')` as three independent, simultaneously-active sources.
   So a re-add with the SAME value is merely redundant; a DIFFERENT value is
   silently ignored by OpenSSH (first `-o` wins), never applied — a trap.

Two other places in the repo also hardcode `-o StrictHostKeyChecking=accept-new`
and are NOT redundant with `ssh_args`: `ansible/roles/bootstrap/tasks/main.yml`'s
post-restart reachability probe and `scripts/ssh.sh` both invoke the `ssh`
binary directly (not through Ansible's connection plugin), so neither reads
ssh_args/ansible_ssh_common_args at all. Keep those copies in sync if this
policy changes.

**Why the bootstrap reachability probe is a raw `ssh` invocation at all.**
The obvious tool — `meta: reset_connection` followed by any Ansible task —
does not prove a fresh handshake under this repo's own `ssh_args`:
`ControlPersist=60s` keeps a control socket alive, `reset_connection` only
*warns* (does not fail) if `ssh -O stop` can't reach that socket, and if the
socket survived, the next task can silently multiplex back onto it — passing
without ever opening a new TCP + auth handshake against the reconfigured
sshd. So the probe bypasses the connection plugin entirely: a raw `ssh`
run with `ControlMaster=no -o ControlPath=none`, which structurally cannot
multiplex onto anything. Host/port/user/key come from the same play
variables (`ansible_host`/`ansible_user`/`ansible_ssh_private_key_file`/
`box.ssh_port`), not hardcoded, so a `BOX_SSH_PORT` change cannot desync
the check from the play.

---

## Firewall single-host guard

**Rule enforced in `ansible/roles/firewall/tasks/main.yml`:** every inbound
rule (any `direction` other than an explicit `out`) must carry a non-empty
`source_ips` where every entry is exactly one host (/32 IPv4 or /128 IPv6).
`port_covers_ssh` does not gate whether the guard runs; it only sharpens
the failure message when the rule also covers `BOX_SSH_PORT`.

**Proof (verified against ansible-core 2.21.1).** The exact `vars:` block was
spliced out of the role and exercised against real Jinja templating:

- **Why a format check and not just string deny-lists.** Rejecting only the
  literal strings `"0.0.0.0/0"` and `"::/0"` is not enough: `"10.0.0.0/8"`,
  `"0.0.0.0/1"`, `"192.0.0.0/2"`, or a bare `"1.2.3.4"` with no prefix are
  all wider than a single host and pass an exact-string check. Hence the
  per-entry `ipv4_slash32` / `ipv6_slash128` patterns.
- **Why regex and not CIDR math.** The `ipaddr` filter needs the python
  `netaddr` library (requirements.txt pins no netaddr) or the ansible.utils
  collection (not vendored). Either is a hard runtime failure on this repo's
  pinned setup.
- **`\Z` not `$`.** `is match()` runs Python `re.match()`, where `$` matches
  true end-of-string OR just before a single trailing `"\n"`. A `$`-anchored
  pattern accepted `"1.2.3.4/32\n"` and `"::1/128\n"` as clean single hosts
  (wrong); `\Z` matches true end-of-string only, so both are rejected.
  Leading-newline, leading/trailing space, trailing tab and `"\r\n"`
  variants were rejected even with `$` (Python's `$` leniency is specifically
  "one trailing LF", not "any trailing junk").
- **`is_range` and `\Z` — the anchor alone was not enough there.** For a
  port `"9000-9500\n"` with a world-open source, `$` made `is_range` True and
  `in_range` True via `| int`'s whitespace-stripping (`"9500\n" | int ==
  9500`) — the guard fired and rejected the rule. `\Z` alone made `is_range`
  False, so `in_range` was never evaluated and the guard was SKIPPED for a
  world-open rule. Therefore `port_str` is trimmed before is_any/is_exact/
  is_range see it, making `\Z` safe everywhere: stray whitespace can only
  ever WIDEN what counts as SSH-covering (now only an error-message concern),
  never widen what is guarded.
- **Empty `source_ips` hard-fails.** Formally "every entry is a single host"
  is true over zero entries, but an inbound rule with no named source is
  either an upstream bug (e.g. IP detection returned nothing) or ambiguous
  about Hetzner's server-side treatment — unverified either way, and this
  guard fails closed on ambiguity.
- **Only an explicit `direction: out` is exempt.** Deliberately not
  `item.direction | default('in') == 'in'`: that form defaults *absent*
  direction to inbound but silently skips the guard for any unrecognised
  value (a typo, or a future direction this file doesn't know), the exact
  near-miss case a backstop should catch. For "anything I don't recognise
  still gets checked", only a value the file positively knows means "not
  inbound" (`out`) turns the check off. An outbound rule uses
  `destination_ips`, not `source_ips`, so without this an outbound rule would
  read as "source_ips empty" and hard-fail even though it is not an
  inbound-exposure question.
- **IPv4 octets, no leading zeros.** `1[0-9]{2}` / `[1-9]?[0-9]` (not
  `[01]?[0-9]?[0-9]`) deliberately matches the sibling `ipv4_strict_regex` in
  `ansible/playbooks/tasks/detect-public-ip.yml`, so `"010.0.0.1/32"` is
  rejected here the same way `"010.0.0.1"` is there. Leading zeros are
  ambiguous in practice, so rejecting rather than guessing is the same
  fail-closed posture.
- **IPv6 is a *shape* check, not full RFC 4291 validation.** Hex groups
  joined by colons, ending literally in `"/128"`. It does not catch every
  malformed form (e.g. more than one `::`) and does not special-case
  embedded-IPv4 forms like `::ffff:1.2.3.4/128`. Hetzner's own API is the
  backstop for full address correctness on apply; this guard's job is only to
  reject anything wider than a single host, in both families.

---

## Volume reattach

**Rule enforced in `ansible/playbooks/create.yml`:** refuse to attach a
volume that is currently on a *different* server unless
`VOLUME_ALLOW_REATTACH=true` is set, and only after that server is stopped.

**Proof (verified against hetzner.hcloud 6.10.0, the vendored collection).**
`hetzner.hcloud.volume`'s `_update_volume()` (plugins/modules/volume.py
**L238-246**) calls `attach()` unconditionally on a server-name mismatch —
no prompt, no guard of its own. What Hetzner's *server-side* API actually
does with a bare attach is NOT verified against the wire contract, but two
pieces of official-client evidence point the same way: Hetzner's own
Terraform provider explicitly Detaches before Attaching when a volume's
server changes (internal/volume/resource.go), and its Go client defines
`ErrorCodeVolumeAlreadyAttached`. Hetzner would not write a conditional
detach in their own provider against their own API if a bare attach silently
moved the volume — so this most likely gets REJECTED outright rather than
yanking a live filesystem out from under whatever is using it.

"Most likely" is not "certainly", and a running box with this volume mounted
is not where you want to find out you were wrong. So `create.yml` refuses by
default regardless of which way it actually fails, converting even an
unlikely bad outcome into a clear message instead of an opaque API error.
`delete_protection` does NOT help here: it blocks `state: absent`, not
`attach()`. Because `volume.name` is deliberately fixed (decoupled from
`BOX_NAME`) while `box.name` is env-driven, this refusal WILL be hit on the
first blue/green `make create` unless explicitly allowed. This is the ONE
canonical place this rationale lives; `.env.example` and `group_vars/all.yml`
only point here.

---

## Detect public IP validation

**Rule enforced in `ansible/playbooks/tasks/detect-public-ip.yml`:** the
answer from ipify must be a well-formed IPv4 address with no leading/trailing
whitespace, and it must not be a private/loopback/link-local/CGNAT/multicast/
reserved address; otherwise it is a hard failure, never a vacuous pass.

**Proof (verified against ansible-core 2.21.1, and the vendored collection
set).** On this box the ONLY inbound protection is the firewall `/32` rule
built from this value, so the source must be trusted. ipify is a third-party,
unauthenticated HTTPS JSON endpoint; a hijacked/proxied/captive-portal answer
can still *parse* as an IPv4 address while being useless or misleading
(`0.0.0.0`, `127.0.0.1`, `169.254.x.x`, RFC1918). ipify only sees the last
public hop of the HTTPS connection reaching it, so it cannot legitimately
return any of those — if one comes back, something other than the real
service answered.

- **`\Z` not `$`** for the same reason as the firewall guard: `$` in
  `re.match()` accepts one trailing `"\n"`, and `{"ip": "1.2.3.4\n"}` is
  valid JSON, so `\Z` is required to stop exactly that trick.
- **Whitespace via string equality, not just the regex.** Also assert the
  value equals its own trimmed form — a structurally different mechanism
  that isn't wrong in the same way a regex anchor can be wrong. It also
  guards the octet checks below, which parse with `map('int')`: Python
  `int()` silently strips whitespace, so a padded value that slipped past the
  regex could otherwise have sailed through classification.
- **No ansible.utils.** `ansible/collections/requirements.yml` pins only
  hetzner.hcloud, ansible.posix and community.general, and there is no
  `ansible_collections/ansible/utils` tree — so `ansible.utils.ipaddr` is not
  available and using it would be a hard runtime failure on this repo's
  pinned setup.

---

## Volume format and order

**Rules enforced in code:** (1) the volume module's `format` param is only
honored on first creation, so a re-run can never reformat/wipe an existing
volume; (2) in `ansible/roles/volume/tasks/main.yml` the mount task runs
FIRST and hard-fails on an unformatted device, so the mkfs-capable
`community.general.filesystem` task is structurally unreachable on such a
device. Do NOT reorder the two volume tasks, and do NOT add `ignore_errors`
to the mount task — either change opens a live path to mkfs'ing an
unformatted-but-attached volume.

**Why.** `AnsibleHCloudVolume._create_volume()` (hetzner.hcloud 6.10.0,
plugins/modules/volume.py) is the only path that reads `format`; once the
volume exists the module takes `_update_volume()`, which never reads it. So
re-runs cannot reformat. `community.general.filesystem` (community.general
13.1.0) IS mkfs-capable: its default `state: present` creates a filesystem on
a device with none. What protects the data is task ORDERING, not the module —
hence the reorder/ignore_errors prohibitions.
