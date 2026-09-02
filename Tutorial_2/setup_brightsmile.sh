#!/usr/bin/env bash
#
# ===========================================================================
#  setup_brightsmile.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, weak credentials,
#  an anonymous-FTP information-leak misconfiguration, a database-stored
#  SSH key leak, and a SUID/PATH-hijack privilege-escalation flaw on the
#  host it runs on.
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
echo " BrightSmile Dental Clinic Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "BrightSmile Dental Clinic" — a small dental practice runs a
# self-hosted appointment-booking server. Front-desk staff share an FTP
# drop-folder for scanned insurance forms, and a junior dev wired the
# booking app straight to MySQL with credentials that were never rotated.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-mysqli php-cli \
    mariadb-server \
    openssh-server \
    vsftpd \
    ufw \
    cron \
    gcc

# --- 2. Users ----------------------------------------------------------------
# Front-desk receptionist account. Weak, dictionary-crackable password
# (present in rockyou.txt) — this is the credential recovered from the
# leaked SSH key later in the chain acting as a decoy path AND the
# intermediate account also reachable directly via SSH brute force practice.
if ! id -u recept >/dev/null 2>&1; then
    useradd -m -s /bin/bash recept
fi
echo "recept:sunflower1" | chpasswd

# Clinic system administrator account — the lateral-movement target. No
# direct password login; reached only via the leaked SSH key found in the
# database (see section 6).
if ! id -u clinicadmin >/dev/null 2>&1; then
    useradd -m -s /bin/bash clinicadmin
fi
usermod -L clinicadmin   # password login disabled; key-only, on purpose

# A third, uninvolved account for realism (not part of the intended path).
if ! id -u dev_owen >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_owen
fi
echo "dev_owen:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: BrightSmile Booking Portal --------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>BrightSmile Dental Clinic - Booking Portal</title></head>
<body style="font-family:sans-serif;">
<h1>BrightSmile Dental Clinic</h1>
<p>Online appointment booking is temporarily unavailable while we migrate
to the new patient system. Please call the front desk.</p>
</body>
</html>
EOF

cat > "${WEBROOT}/db_config.php" <<'EOF'
<?php
// BrightSmile Booking Portal - DB connection config
// TODO(owen): rotate this before go-live, using shared dev DB for now
$DB_HOST = "127.0.0.1";
$DB_USER = "booking_app";
$DB_PASS = "Fl0ss_Daily!";
$DB_NAME = "brightsmile";
?>
EOF

# --- 4. Initial-access vulnerability: anonymous FTP drop-folder -------------
# Front-desk staff use FTP to exchange scanned insurance forms with the
# billing contractor. Anonymous read/write was left enabled "temporarily"
# during setup and never disabled. The EASY flag sits in plain view, and a
# leftover sync script reveals the DB credentials that power lateral
# movement in Part 4 (a *different* copy of the same DB_PASS above,
# demonstrating credential reuse across the leak).
mkdir -p /srv/ftp/patient_forms /srv/ftp/staff_notes
cat > /srv/ftp/staff_notes/EASY_FLAG.txt <<'EOF'
BSM{4N0NYM0US-FTP-1S-N0T-A-F1L3-SH4R3}
EOF

cat > /srv/ftp/staff_notes/reminder_sync.sh.bak <<'EOF'
#!/usr/bin/env bash
# old appointment-reminder sync job - replaced by cron, keeping for reference
# connects to the booking DB to pull tomorrow's appointments
mysql -u booking_app -p'Fl0ss_Daily!' brightsmile -e "SELECT * FROM appointments WHERE appt_date = CURDATE() + INTERVAL 1 DAY;"
# NOTE: same creds as db_config.php, do not change one without the other
EOF

chown -R ftp:ftp /srv/ftp
chmod -R 755 /srv/ftp
chmod 644 /srv/ftp/staff_notes/EASY_FLAG.txt /srv/ftp/staff_notes/reminder_sync.sh.bak

cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
anon_root=/srv/ftp
anon_upload_enable=NO
anon_mkdir_write_enable=NO
local_enable=NO
write_enable=NO
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
EOF
systemctl restart vsftpd

# --- 5. Database used by the web app -----------------------------------------
mysql -u root <<'EOF'
CREATE DATABASE IF NOT EXISTS brightsmile;
CREATE USER IF NOT EXISTS 'booking_app'@'localhost' IDENTIFIED BY 'Fl0ss_Daily!';
GRANT ALL PRIVILEGES ON brightsmile.* TO 'booking_app'@'localhost';
FLUSH PRIVILEGES;

USE brightsmile;
CREATE TABLE IF NOT EXISTS appointments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    patient_name VARCHAR(100),
    appt_date DATE
);
INSERT INTO appointments (patient_name, appt_date) VALUES
    ('J. Alvarez', CURDATE() + INTERVAL 1 DAY),
    ('R. Okafor', CURDATE() + INTERVAL 1 DAY);

CREATE TABLE IF NOT EXISTS staff_credentials (
    id INT AUTO_INCREMENT PRIMARY KEY,
    label VARCHAR(100),
    note TEXT,
    payload_b64 TEXT
);
EOF

# --- 6. Intermediate vulnerability: SSH private key leaked via the DB ------
# clinicadmin's SSH private key was pasted into a "staff_credentials" table
# during an IT handover and base64-encoded "for safety" (it is not safe).
# An attacker who reaches recept (via the FTP-leaked SSH password) can
# authenticate to MySQL with the *same* booking_app credential found in
# db_config.php / reminder_sync.sh.bak, query the table, base64-decode the
# payload, and use it to SSH in as clinicadmin.
ssh-keygen -t ed25519 -N "" -f /tmp/clinicadmin_key -C "clinicadmin@brightsmile" -q
mkdir -p /home/clinicadmin/.ssh
cp /tmp/clinicadmin_key.pub /home/clinicadmin/.ssh/authorized_keys
chown -R clinicadmin:clinicadmin /home/clinicadmin/.ssh
chmod 700 /home/clinicadmin/.ssh
chmod 600 /home/clinicadmin/.ssh/authorized_keys

PRIVKEY_B64=$(base64 -w0 /tmp/clinicadmin_key)
mysql -u root brightsmile -e \
  "INSERT INTO staff_credentials (label, note, payload_b64) VALUES ('clinicadmin_handover', 'IT handover key, base64 for safe storage - remove after onboarding', '${PRIVKEY_B64}');"
rm -f /tmp/clinicadmin_key /tmp/clinicadmin_key.pub

cat > /home/recept/INTERMEDIATE_FLAG.txt <<'EOF'
BSM{DB_CR3DS_D0NT_ST0P_AT_TH3_W3B_APP}
EOF
chown recept:recept /home/recept/INTERMEDIATE_FLAG.txt
chmod 600 /home/recept/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: SUID binary + PATH hijack ------
# clinicadmin can run a "clinic-diagnostics" helper that was built SUID-root
# for convenience so front-desk hardware checks don't need sudo prompts.
# It shells out to `whoami` and `uptime` WITHOUT an absolute path, so it
# trusts the caller's $PATH — a classic PATH-hijack privilege escalation,
# distinct from GreenGrid's sudo NOPASSWD/GTFOBins pivot.
cat > /tmp/clinic_diag.c <<'EOF'
#include <stdlib.h>
#include <stdio.h>

int main() {
    printf("BrightSmile Clinic Diagnostics\n");
    printf("-------------------------------\n");
    system("whoami");
    system("uptime");
    return 0;
}
EOF
gcc -o /usr/local/bin/clinic-diagnostics /tmp/clinic_diag.c
chown root:root /usr/local/bin/clinic-diagnostics
chmod 4755 /usr/local/bin/clinic-diagnostics
rm -f /tmp/clinic_diag.c

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
BSM{S3T-UID-M3ANS-TRUST-Y0UR-PATH-CAR3FULLY}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
mkdir -p /var/log/brightsmile
cat > /etc/cron.d/brightsmile-heartbeat <<'EOF'
* * * * * root echo "booking sync heartbeat $(date)" >> /var/log/brightsmile/sync.log
EOF
chmod 644 /etc/cron.d/brightsmile-heartbeat

# --- 10. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 21/tcp    # FTP control
ufw allow 20/tcp    # FTP data (active mode)
ufw allow 30000:31000/tcp  # vsftpd passive port range (optional, harmless if unused)
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable

# --- 11. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 mariadb vsftpd >/dev/null 2>&1 || true
systemctl restart ssh apache2 mariadb vsftpd

cat <<'EOF'

===================================================================
 BrightSmile Dental Clinic lab target build complete.

 Exposed services: FTP (21, anonymous), SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
