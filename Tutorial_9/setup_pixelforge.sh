#!/usr/bin/env bash
#
# ===========================================================================
#  setup_pixelforge.sh   —   Tutorial 9: PixelForge Print Shop
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, an unauthenticated
#  OS command injection in an order-tracking page, a weak/reused password
#  sourced from rockyou.txt, an unauthenticated Redis job queue leaking a
#  second staff credential, and a docker-group privilege-escalation flaw on
#  the host it runs on.
#
#  RUN THIS ONLY ON:
#    - A freshly installed, throwaway Ubuntu Server VM
#    - Inside an isolated/host-only or NAT'd lab network, with NO
#      internet-facing NIC
#    - A VM you are prepared to snapshot and destroy afterward
#
#  DO NOT run this on a production system, a cloud instance with a public
#  IP, or any host reachable from the internet. Doing so will create a
#  genuinely exploitable machine.
#
#  Intended use: authorized security training / CTF-style practice only.
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
#  Target Information (fill in after first boot, for your own lab notes —
#  matches the "Target Information" table at the top of the paired
#  walkthrough, PixelForge_Print_Shop_Walkthrough.md):
#
#    Lab name                  : PixelForge Print Shop
#    Target service            : Apache/PHP + Redis (localhost-only) + SSH
#    Target IP address         : <fill in after boot, e.g. `ip a`>
#    Attacker Kali IP address  : <your attacker VM's isolated-network IP>
#
#  Objective: identify and exploit three intended vulnerabilities on this
#  training VM — an Easy flag via OS-command-injection-leaked staff
#  credentials, an Intermediate flag via an unauthenticated Redis job
#  queue leaking a second staff password, and a Hard privilege-escalation
#  path via docker-group socket abuse. See the paired walkthrough for the
#  full step-by-step attack path.
# ---------------------------------------------------------------------------

echo "==================================================================="
echo " PixelForge Print Shop — Lab Target Installer (Tutorial 9)"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "PixelForge Print Shop" — a small print-and-design shop's
# self-hosted order-tracking site. Customers can check an order's status
# by order ID; the page shells out to a local lookup script and passes the
# order ID straight through, unsanitized — a textbook OS command
# injection. That foothold reveals a `.env` file with a print-operator's
# shell password. The print-ops account talks to an internal Redis job
# queue with no authentication configured, and one queued job's notes
# field leaks a second staff member's (a freelance designer's) password
# in plain text. The designer account was added to the `docker` group for
# convenience so they could rebuild a container image themselves — which,
# because the Docker Engine socket is root-equivalent, hands them (and
# anyone who lands their shell) a straightforward path to root.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-cli \
    redis-server \
    openssh-server \
    ufw \
    cron \
    ca-certificates curl gnupg

# Docker Engine (needed for the intended privilege-escalation path in
# Part 5). Installed from the official Docker apt repository.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# --- 2. Users ----------------------------------------------------------------
# Print-operator account. Weak, dictionary-crackable password — a genuine
# rockyou.txt entry — set here as the account's real login password so the
# credential recovered via command injection in Part 3 actually works.
if ! id -u printops >/dev/null 2>&1; then
    useradd -m -s /bin/bash printops
fi
echo "printops:trustno1" | chpasswd

# Freelance designer account — the lateral-movement target. Its real
# login password is set here (so the credential recovered from Redis in
# Part 4 actually works), but nothing points to it until the job queue is
# inspected. Also a genuine rockyou.txt entry.
if ! id -u designer >/dev/null 2>&1; then
    useradd -m -s /bin/bash designer
fi
echo "designer:sunflower1" | chpasswd

# Added for convenience so the designer can rebuild their own container
# image without bothering an admin. THE privilege-escalation bug: docker
# group membership is root-equivalent, since the Docker Engine socket
# lets its members launch containers with arbitrary host bind-mounts.
usermod -aG docker designer

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u mgr_dana >/dev/null 2>&1; then
    useradd -m -s /bin/bash mgr_dana
fi
echo "mgr_dana:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: PixelForge order tracker ----------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>PixelForge Print Shop</title></head>
<body style="font-family:sans-serif;">
<h1>PixelForge Print Shop</h1>
<p>Check the status of your print order.</p>
<form method="get" action="track.php">
  Order ID: <input name="order_id">
  <input type="submit" value="Check Status">
</form>
</body>
</html>
EOF

# Local helper the tracker page shells out to. Deliberately simple: it
# just greps a flat "orders" status file for the given ID.
mkdir -p /opt/pixelforge
cat > /opt/pixelforge/orders.txt <<'EOF'
PF-1001:Printing
PF-1002:Ready for pickup
PF-1003:Shipped
EOF
cat > /opt/pixelforge/track_lookup.sh <<'EOF'
#!/usr/bin/env bash
# PixelForge order status lookup helper
grep "^$1:" /opt/pixelforge/orders.txt || echo "Order not found."
EOF
chmod 755 /opt/pixelforge/track_lookup.sh
chown -R www-data:www-data /opt/pixelforge

# The ONE initial-access vulnerability on this box: track.php passes the
# "order_id" GET parameter straight into shell_exec() with no validation
# and no escaping, so shell metacharacters in the parameter are
# interpreted by the shell instead of treated as literal order-ID text —
# a textbook OS command injection.
cat > "${WEBROOT}/track.php" <<'EOF'
<?php
// PixelForge order tracker
// TODO(web contractor, unreviewed): sanitize order_id before go-live
$order_id = $_GET['order_id'] ?? '';
$output = shell_exec("/opt/pixelforge/track_lookup.sh " . $order_id);
echo "<h2>Order Status</h2><pre>" . htmlspecialchars($output) . "</pre>";
?>
EOF

# .env file leaked to www-data's reach: real-world sloppiness pattern of
# dropping deploy/service credentials next to the app instead of using a
# secrets manager. Readable by www-data, which is exactly the identity
# the command injection runs as.
cat > "${WEBROOT}/.env" <<'EOF'
# PixelForge site environment (do not commit - nobody checked)
APP_ENV=production
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
# shell login for order-desk staff maintenance tasks:
PRINTOPS_USER=printops
PRINTOPS_PASS=trustno1
EOF
chmod 644 "${WEBROOT}/.env"

chown -R www-data:www-data "${WEBROOT}"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 4. Easy flag: reachable shortly after SSH login as printops -----------
cat > /home/printops/EASY_FLAG.txt <<'EOF'
PFP{SH3LL_3XEC-N3V3R-TRUST5-USER-1NPUT}
EOF
chown printops:printops /home/printops/EASY_FLAG.txt
chmod 600 /home/printops/EASY_FLAG.txt

# --- 5. Redis job queue: internal print/design job pipeline -----------------
systemctl enable redis-server >/dev/null 2>&1 || true

# Redis binds to localhost only by default on Debian/Ubuntu packages, and
# stays that way here (never exposed to the network) — the intermediate
# bug is that "requirepass" is left unset (the package default), so any
# local process can run commands against it with zero authentication.
systemctl restart redis-server

# --- 6. Intermediate vulnerability: unauthenticated Redis job queue
#         leaking a second staff credential (lateral movement, distinct
#         from the command injection used for initial access) --------------
# The order-tracking backend queues design jobs in a Redis list. No
# "requirepass" was ever set on this internal-only service, so anyone who
# can reach 127.0.0.1:6379 (e.g. as printops, once local) can read every
# queued job. One job's freeform "notes" field is a leftover pasted
# credential from an old handover message that was never redacted.
redis-cli rpush design_jobs '{"job":"PF-2041","client":"Rosewood Cafe","notes":"logo redraw, rush order"}' >/dev/null
redis-cli rpush design_jobs '{"job":"PF-2042","client":"Internal","notes":"handover: designer account is designer / sunflower1, remove this note!"}' >/dev/null
redis-cli rpush design_jobs '{"job":"PF-2043","client":"Bloom & Co","notes":"business card reprint"}' >/dev/null

cat > /home/designer/INTERMEDIATE_FLAG.txt <<'EOF'
PFP{1NT3RNAL-QU3U3S-N33D-AUTH-T00}
EOF
chown designer:designer /home/designer/INTERMEDIATE_FLAG.txt
chmod 600 /home/designer/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: docker-group socket abuse
#         (distinct from every other primitive used in this lab set: not
#         SUID/PATH hijack, not sudo NOPASSWD/GTFOBins, not a writable
#         script/unit, not a module-path hijack, not tar-wildcard
#         injection, not a misassigned capability, not an LD_PRELOAD
#         sudoers leak) -----------------------------------------------------
# designer is a member of the "docker" group so they can rebuild their
# own container image without needing sudo. Membership in that group is
# root-equivalent: the Docker Engine socket (/var/run/docker.sock) lets
# its members launch containers with arbitrary host bind-mounts, and a
# container that bind-mounts "/" can chroot into it to obtain a root
# shell on the underlying host — no exploit code required, just Docker
# doing exactly what it's designed to do for anyone who can talk to the
# socket.
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
PFP{D0CK3R-GR0UP-1S-R00T-1N-D1SGU1S3}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 8. Harmless cron job for realism (not part of intended path) -----------
mkdir -p /var/log/pixelforge
cat > /etc/cron.d/pixelforge-heartbeat <<'EOF'
* * * * * root echo "print queue heartbeat $(date)" >> /var/log/pixelforge/heartbeat.log
EOF
chmod 644 /etc/cron.d/pixelforge-heartbeat

# --- 9. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable  # note: Redis/6379 is bound to localhost only, never exposed

# --- 10. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 cron redis-server docker >/dev/null 2>&1 || true
systemctl restart ssh apache2 cron redis-server docker

cat <<'EOF'

===================================================================
 PixelForge Print Shop lab target build complete (Tutorial 9).

 Exposed services: SSH (22), HTTP (80)
 Redis (6379) is bound to localhost only — not network-exposed.
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
