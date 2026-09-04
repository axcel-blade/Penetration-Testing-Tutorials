#!/usr/bin/env bash
#
# ===========================================================================
#  setup_makernest.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, weak credentials,
#  a path-traversal file-read web vulnerability, a crackable password hash
#  leaked via a world-readable legacy auth file, and a tar-wildcard-injection
#  privilege-escalation flaw on the host it runs on.
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
echo " MakerNest Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "MakerNest" — a fictional community makerspace's self-hosted tool
# reservation kiosk. Members book time on shared equipment (3D printers,
# laser cutters, etc.) through a small PHP kiosk app. The "export report"
# feature takes a filename straight from a query parameter and never
# canonicalizes it, so it happily reads anything the web server user can
# see — including a config file outside the report directory that still
# has an operator password sitting in it in plaintext. Separately, a
# long-deprecated Apache Basic-Auth file for the old admin tools page was
# never deleted, and a group-writable staging directory used by a nightly
# root archive job turns out to be a classic tar-wildcard trap.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-cli \
    openssh-server \
    ufw \
    cron

# --- 2. Users ----------------------------------------------------------------
# Front-desk kiosk operator account. Weak, dictionary-crackable password —
# genuinely present in the project's rockyou.txt (confirmed at line 926,
# "butterfly1") — consistent with the lab convention of using real
# wordlist-crackable credentials rather than made-up strings.
if ! id -u kiosk_ops >/dev/null 2>&1; then
    useradd -m -s /bin/bash kiosk_ops
fi
echo "kiosk_ops:butterfly1" | chpasswd

# Equipment-maintenance service account — the lateral-movement target.
# Its real login password is set here (so the crackable hash recovered
# later actually works), but it has no lead pointing to it until the
# legacy auth file is found in Part 4.
if ! id -u toolsmith >/dev/null 2>&1; then
    useradd -m -s /bin/bash toolsmith
fi
echo "toolsmith:chocolate1" | chpasswd

# Dedicated group for the nightly archive job's staging directory
# (section 7) — this is what makes the privilege-escalation bug possible.
groupadd -f makerops
usermod -aG makerops toolsmith

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dev_soren >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_soren
fi
echo "dev_soren:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: MakerNest Tool Reservation Kiosk --------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>MakerNest - Tool Reservation Kiosk</title></head>
<body style="font-family:sans-serif;">
<h1>MakerNest Makerspace</h1>
<p>Reserve shared equipment (3D printers, laser cutter, CNC mill) below.
Staff: usage reports are available from the kiosk export tool.</p>
<p><a href="kiosk/export.php?report=weekly_usage.txt">View weekly usage report</a></p>
</body>
</html>
EOF

mkdir -p "${WEBROOT}/kiosk"
mkdir -p /var/lib/makernest/reports

cat > /var/lib/makernest/reports/weekly_usage.txt <<'EOF'
MakerNest Weekly Equipment Usage
---------------------------------
3D Printer (Bay 1): 34 reservations
Laser Cutter: 19 reservations
CNC Mill: 7 reservations
EOF

# Path-traversal / arbitrary file read: the "report" parameter is joined
# directly onto the reports directory with no canonicalization, so a
# caller can walk out of /var/lib/makernest/reports with "../" and read
# any file the www-data user can see.
cat > "${WEBROOT}/kiosk/export.php" <<'EOF'
<?php
// MakerNest Kiosk - report export
// NOTE(intern project, Aug): quick-and-dirty for the open day demo,
// tighten this up before it goes anywhere near the public network.
$base = '/var/lib/makernest/reports/';
$report = isset($_GET['report']) ? $_GET['report'] : 'weekly_usage.txt';
$path = $base . $report;
if (file_exists($path)) {
    header('Content-Type: text/plain');
    readfile($path);
} else {
    echo "Report not found.";
}
?>
EOF

chown -R www-data:www-data "${WEBROOT}/kiosk" /var/lib/makernest/reports
chmod 755 "${WEBROOT}/kiosk"
chmod 644 /var/lib/makernest/reports/weekly_usage.txt

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 4. Initial-access vulnerability: leaked operator credential --------
# Sitting outside the web root but still readable by www-data (and thus
# reachable through the export.php path-traversal bug) is the kiosk's
# own config file, with the front-desk login left in plaintext.
mkdir -p /etc/makernest
cat > /etc/makernest/kiosk.conf <<'EOF'
; MakerNest kiosk terminal config
; local front-desk login used to unlock the reservation terminal each morning
kiosk_user = kiosk_ops
kiosk_pass = butterfly1
EOF
chown root:www-data /etc/makernest/kiosk.conf
chmod 640 /etc/makernest/kiosk.conf

# --- 5. Easy flag: reachable immediately after logging in as kiosk_ops -----
cat > /home/kiosk_ops/EASY_FLAG.txt <<'EOF'
MKN{PATH-TRAV3RSAL-R34DS-WHAT3V3R-WWW-DATA-CAN}
EOF
chown kiosk_ops:kiosk_ops /home/kiosk_ops/EASY_FLAG.txt
chmod 600 /home/kiosk_ops/EASY_FLAG.txt

# --- 6. Intermediate vulnerability: crackable hash in a leftover legacy
#         auth file (lateral movement, distinct from the web path-
#         traversal used for initial access) -------------------------------
# Before the kiosk app existed, equipment staff used an Apache Basic-Auth
# gated "admin tools" page. It was retired and the .htaccess removed, but
# the .htpasswd-style credential file was never deleted, and it's still
# sitting world-readable in a backups folder. It holds a real SHA-512
# crypt hash — not an encoding like base64/hex — so this box exercises
# offline hash cracking (John the Ripper) rather than decoding.
mkdir -p /var/backups/makernest
TOOLSMITH_HASH=$(openssl passwd -6 -salt makernest chocolate1)
cat > /var/backups/makernest/toolsmith.htpasswd <<EOF
# legacy admin-tools basic-auth file - retired 2024, .htaccess removed
# TODO: delete this file, it's no longer used (never actioned)
toolsmith:${TOOLSMITH_HASH}
EOF
chown root:root /var/backups/makernest/toolsmith.htpasswd
chmod 644 /var/backups/makernest/toolsmith.htpasswd
chmod 755 /var/backups/makernest

cat > /home/toolsmith/INTERMEDIATE_FLAG.txt <<'EOF'
MKN{CRYPT-HASH3S-N33D-CR4CK1NG-N0T-D3C0D1NG}
EOF
chown toolsmith:toolsmith /home/toolsmith/INTERMEDIATE_FLAG.txt
chmod 600 /home/toolsmith/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: tar wildcard injection via a
#         group-writable archive staging directory (distinct from every
#         other primitive used in this lab set: not sudo/GTFOBins, not
#         SUID/PATH-hijack, not a writable script/unit, not a capability)
# --------------------------------------------------------------------------
# A nightly (lab-speed: every minute) root cron job archives whatever
# equipment-usage exports have been staged by the maintenance crew. The
# staging directory is group-writable by "makerops" so toolsmith can drop
# files there without bothering an admin — but the archive script runs
# `tar -czf ... *` with a shell-expanded wildcard inside that directory.
# Any member of makerops can plant files named like tar options
# (--checkpoint=1, --checkpoint-action=exec=...) to get tar to execute an
# arbitrary command as root the next time the job fires.
mkdir -p /var/lib/makernest/export_stage
chown root:makerops /var/lib/makernest/export_stage
chmod 775 /var/lib/makernest/export_stage   # group-writable: THE bug

cat > /usr/local/sbin/makernest_archive.sh <<'EOF'
#!/usr/bin/env bash
# MakerNest nightly export archiver (lab-speed: runs every minute)
cd /var/lib/makernest/export_stage || exit 1
tar -czf /var/backups/makernest-exports.tar.gz * 2>/dev/null
EOF
chmod 755 /usr/local/sbin/makernest_archive.sh

cat > /etc/cron.d/makernest-archive <<'EOF'
* * * * * root /usr/local/sbin/makernest_archive.sh
EOF
chmod 644 /etc/cron.d/makernest-archive

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
MKN{TAR-W1LDC4RD-1NJ3CT10N-1S-ST1LL-A-CLASS1C}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
mkdir -p /var/log/makernest
cat > /etc/cron.d/makernest-heartbeat <<'EOF'
* * * * * root echo "kiosk heartbeat $(date)" >> /var/log/makernest/heartbeat.log
EOF
chmod 644 /etc/cron.d/makernest-heartbeat

# --- 10. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable

# --- 11. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 cron >/dev/null 2>&1 || true
systemctl restart ssh apache2 cron

cat <<'EOF'

===================================================================
 MakerNest lab target build complete.

 Exposed services: SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
