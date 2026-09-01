#!/usr/bin/env bash
#
# ===========================================================================
#  setup_greengrid.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, weak credentials,
#  a leaked-secret web misconfiguration, and a sudo privilege-escalation
#  flaw on the host it runs on.
#
#  RUN THIS ONLY ON:
#    - A freshly installed, throwaway Ubuntu Server VM
#    - Inside an isolated/NAT'd lab network with NO internet-facing NIC
#    - A VM you are prepared to destroy afterward
#
#  DO NOT run this on a production system, a cloud instance with a public
#  IP, or any host that is reachable from the internet. Doing so will
#  create a genuinely exploitable machine.
#
#  Intended use: authorized security training / CTF-style practice only.
# ===========================================================================

set -euo pipefail

echo "==================================================================="
echo " GreenGrid Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "GreenGrid" — a fictional startup that makes a web portal for
# monitoring soil-moisture / greenhouse sensors for small urban farms.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-mysqli php-cli \
    mariadb-server \
    openssh-server \
    git \
    ufw \
    cron

# --- 2. Users ----------------------------------------------------------------
# Low-privilege operational account used by the (fictional) on-call
# greenhouse technician. Weak, dictionary-crackable password (present in
# rockyou.txt) for lab purposes — consistent with the ISEC3002 lab
# convention of using genuinely wordlist-crackable credentials.
if ! id -u ggtech >/dev/null 2>&1; then
    useradd -m -s /bin/bash ggtech
fi
echo "ggtech:sunshine" | chpasswd

# A second, "normal" low-priv account with a strong password, just for
# realism (not part of the intended path).
if ! id -u dev_amara >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_amara
fi
echo "dev_amara:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: GreenGrid Sensor Portal -----------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>GreenGrid Sensor Portal</title></head>
<body style="font-family:sans-serif;">
<h1>GreenGrid Sensor Portal</h1>
<p>Login for greenhouse technicians.</p>
<form method="post" action="login.php">
  Username: <input name="user"><br>
  Password: <input name="pass" type="password"><br>
  <input type="submit" value="Log in">
</form>
</body>
</html>
EOF

cat > "${WEBROOT}/config.php" <<'EOF'
<?php
// GreenGrid Sensor Portal - DB connection config
$DB_HOST = "127.0.0.1";
$DB_USER = "gg_app";
$DB_PASS = "H0useplant!99";
$DB_NAME = "greengrid";
?>
EOF

cat > "${WEBROOT}/login.php" <<'EOF'
<?php
require_once("config.php");
// NOTE: authentication logic intentionally simplified for demo build.
$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME);
if ($mysqli->connect_errno) {
    echo "Service temporarily unavailable.";
    exit;
}
echo "Login processing is not yet implemented in this build.";
?>
EOF

# EASY FLAG: sits in the web root behind a semi-hidden path, discoverable
# via directory brute-forcing. Rewards basic enumeration before any
# exploitation happens.
mkdir -p "${WEBROOT}/notes"
cat > "${WEBROOT}/notes/EASY_FLAG.txt" <<'EOF'
GG{EN4M3RATE-B3F0R3-Y0U-3XPL0IT}
EOF

# --- 4. Initial-access vulnerability: exposed .git repository ---------------
# The devs deployed straight from a git checkout and never removed .git.
# The repo history contains an old commit with working DB creds that were
# later "rotated" in config.php but reused as the ggtech SSH password.
cd "${WEBROOT}"
git init -q
git config user.email "ci@greengrid.local"
git config user.name "GreenGrid CI"
git add index.php login.php notes
git commit -q -m "Initial portal deploy"

# Simulate an earlier, leakier commit still sitting in history:
cat > "${WEBROOT}/config.php.bak" <<'EOF'
<?php
// old config - superseded, kept for rollback reference
$DB_HOST = "127.0.0.1";
$DB_USER = "gg_app";
$DB_PASS = "H0useplant!99";
$DB_NAME = "greengrid";
// technician SSH fallback account for on-call access:
// ggtech / sunshine
?>
EOF
git add config.php.bak
git commit -q -m "backup config before password rotation (remove before prod!!)"
# "Forget" to remove it — leave .git world-readable via Apache.
# Generate dumb-HTTP server info so plain `git clone` works over Apache.
git update-server-info
chmod -R o+r "${WEBROOT}/.git"

# Apache config: allow directory listing on /notes and don't block .git
a2enmod rewrite >/dev/null
cat > /etc/apache2/conf-available/greengrid.conf <<'EOF'
<Directory /var/www/html/notes>
    Options +Indexes
    Require all granted
</Directory>
<Directory /var/www/html/.git>
    Require all granted
</Directory>
EOF
a2enconf greengrid >/dev/null
systemctl restart apache2

# --- 5. Database used by the web app -----------------------------------------
mysql -u root <<'EOF'
CREATE DATABASE IF NOT EXISTS greengrid;
CREATE USER IF NOT EXISTS 'gg_app'@'localhost' IDENTIFIED BY 'H0useplant!99';
GRANT ALL PRIVILEGES ON greengrid.* TO 'gg_app'@'localhost';
FLUSH PRIVILEGES;
EOF

# --- 6. Intermediate flag: reachable after landing the ggtech shell ---------
cat > /home/ggtech/INTERMEDIATE_FLAG.txt <<'EOF'
GG{L34K3D-CR3D5-G3T-Y0U-1N}
EOF
chown ggtech:ggtech /home/ggtech/INTERMEDIATE_FLAG.txt
chmod 600 /home/ggtech/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: sudo NOPASSWD on a "helper" -----
# ggtech is allowed to run a sensor-log maintenance script as root, no
# password required. The script is meant to just tail/rotate logs, but it
# takes a filename argument that is passed unsanitized to `less`, giving
# an attacker a root shell via a standard GTFOBins-style pivot.
cat > /usr/local/sbin/gg_logview.sh <<'EOF'
#!/usr/bin/env bash
# GreenGrid log maintenance helper.
# Usage: gg_logview.sh <logfile under /var/log/greengrid>
LOGFILE="$1"
if [[ -z "$LOGFILE" ]]; then
    echo "Usage: $0 <logfile>"
    exit 1
fi
less "/var/log/greengrid/${LOGFILE}"
EOF
chmod 755 /usr/local/sbin/gg_logview.sh

mkdir -p /var/log/greengrid
echo "sensor uplink nominal $(date)" > /var/log/greengrid/uplink.log
chmod 644 /var/log/greengrid/uplink.log

cat > /etc/sudoers.d/greengrid <<'EOF'
ggtech ALL=(root) NOPASSWD: /usr/local/sbin/gg_logview.sh *
EOF
chmod 440 /etc/sudoers.d/greengrid

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
GG{GTF0B1NS-L3SS-1S-M0R3-R00T}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
cat > /etc/cron.d/greengrid-uplink <<'EOF'
* * * * * root echo "uplink heartbeat $(date)" >> /var/log/greengrid/uplink.log
EOF
chmod 644 /etc/cron.d/greengrid-uplink

# --- 10. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable

# --- 11. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 mariadb >/dev/null 2>&1 || true
systemctl restart ssh apache2 mariadb

cat <<'EOF'

===================================================================
 GreenGrid lab target build complete.

 Exposed services: SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF