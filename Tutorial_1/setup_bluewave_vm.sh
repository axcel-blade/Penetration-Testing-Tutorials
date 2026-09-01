#!/bin/bash
###############################################################################
# "BLUEWAVE" — Intentionally Vulnerable Ubuntu Target
#
# Purpose : Build a deliberately-misconfigured Ubuntu Server VM for use as a
#           CTF-style pentesting-lab target, for isolated-lab use only.
#
# Theme   : A fictional small logistics company's internal server, exposing
#           a stale internal tool, a leftover Git repo, and a cron-job
#           privilege-escalation path. No relation to any other lab box.
#
# WARNING : This script intentionally weakens the system. Run only inside an
#           isolated lab network (host-only / NAT network / your unit's
#           cloud sandbox). Never on a production or internet-facing host.
#
# Usage   : sudo bash setup_bluewave_vm.sh
# Tested  : Ubuntu Server 22.04 / 24.04, run as root on a fresh VM.
###############################################################################

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0"
  exit 1
fi

echo "[*] Updating package lists..."
apt-get update -y

echo "[*] Installing target services (Apache, PHP, Git, OpenSSH, cron)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 php php-cli libapache2-mod-php \
  openssh-server git cron curl unzip

###############################################################################
# 1. LOW-PRIVILEGE ACCOUNTS
###############################################################################
echo "[*] Creating accounts..."
id -u dpatel &>/dev/null || useradd -m -s /bin/bash dpatel
echo "dpatel:logistics01" | chpasswd

id -u svc-report &>/dev/null || useradd -m -s /bin/bash svc-report

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

###############################################################################
# 2. WEB APP WITH AN EXPOSED .git DIRECTORY
#    Common real-world finding: a deployed web app that still has its .git
#    metadata reachable over HTTP, leaking source and commit history
#    (including a hardcoded credential in an old commit).
###############################################################################
echo "[*] Deploying internal tracking-portal web app with an exposed .git repo..."
APPDIR=/var/www/html/portal
rm -rf /var/www/html/*
mkdir -p "$APPDIR"
cd "$APPDIR"

git init -q
git config user.email "dev@bluewave.local"
git config user.name "Bluewave Dev"

cat > index.php <<'EOF'
<?php
echo "<h1>Bluewave Logistics - Shipment Tracking Portal</h1>";
echo "<p>Internal use only. Contact IT if you need access restored.</p>";
EOF
git add index.php
git commit -q -m "initial portal page"

# An old commit accidentally hardcodes a DB credential, later "removed" —
# but still recoverable from git history/log, which is the actual finding.
cat > config.php <<'EOF'
<?php
// TODO: move this to environment variables before launch
$db_user = "svc-report";
$db_pass = "R3port!ng2024";
EOF
git add config.php
git commit -q -m "add temporary db config (remove before launch)"

# "Fix" that removes the file from disk but leaves it in git history
rm config.php
git add -A
git commit -q -m "remove temp config file"

chown -R www-data:www-data "$APPDIR"
find "$APPDIR" -type d -exec chmod 755 {} \;
find "$APPDIR" -type f -exec chmod 644 {} \;
# Make .git actually servable over HTTP (the misconfiguration)
chmod -R o+rX "$APPDIR/.git"

systemctl restart apache2

###############################################################################
# 3. CRON JOB PRIVILEGE ESCALATION
#    root's crontab runs a script from a world-writable location — classic
#    real-world misconfiguration, distinct from sudo/SUID abuse.
###############################################################################
echo "[*] Planting cron-based privilege escalation..."
mkdir -p /opt/bluewave-scripts
cat > /opt/bluewave-scripts/daily_report.sh <<'EOF'
#!/bin/bash
# Generates the daily shipment report (placeholder)
echo "Report generated at $(date)" >> /var/log/bluewave-report.log
EOF
chmod 777 /opt/bluewave-scripts/daily_report.sh
chmod 777 /opt/bluewave-scripts

# root's crontab executes it every minute
( crontab -l 2>/dev/null; echo "* * * * * /opt/bluewave-scripts/daily_report.sh" ) | crontab -

###############################################################################
# 4. FLAGS
###############################################################################
echo "[*] Planting flags..."
echo "user_flag{git_history_never_really_forgets}" > /home/dpatel/user.txt
chown dpatel:dpatel /home/dpatel/user.txt
chmod 644 /home/dpatel/user.txt

mkdir -p /root
echo "root_flag{cron_jobs_trust_too_much}" > /root/root.txt
chmod 600 /root/root.txt

###############################################################################
# 5. FIREWALL / SCOPE
###############################################################################
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw --force enable || true
fi

echo ""
echo "=================================================================="
echo "  BLUEWAVE target build complete."
echo "  Open services : 22/tcp (ssh), 80/tcp (http)"
echo "  DO NOT expose this VM outside your isolated lab network."
echo "=================================================================="
