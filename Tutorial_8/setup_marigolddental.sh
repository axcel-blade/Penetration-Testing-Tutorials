#!/usr/bin/env bash
#
# ===========================================================================
#  setup_marigolddental.sh   —   Tutorial 8: Marigold Family Dental
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, an unauthenticated
#  SQL injection in a patient-search page, a plaintext staff credential
#  reused for a shell account, a symmetrically-encrypted credential blob
#  decryptable with a key left in an adjacent file, and a sudoers rule that
#  leaks LD_PRELOAD into a privileged command, on the host it runs on.
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
#  walkthrough, Marigold_Dental_Walkthrough.md):
#
#    Lab name                  : Marigold Family Dental
#    Target service            : Apache/PHP + MariaDB (localhost-only) + SSH
#    Target IP address         : <fill in after boot, e.g. `ip a`>
#    Attacker Kali IP address  : <your attacker VM's isolated-network IP>
#
#  Objective: identify and exploit three intended vulnerabilities on this
#  training VM — an Easy flag via SQL-injection-leaked staff credentials
#  reused over SSH, an Intermediate flag via decrypting a credential blob
#  whose key was left in a neighboring backup file, and a Hard
#  privilege-escalation path via an LD_PRELOAD leak in a sudoers rule.
#  See the paired walkthrough for the full step-by-step attack path.
# ---------------------------------------------------------------------------

echo "==================================================================="
echo " Marigold Family Dental — Lab Target Installer (Tutorial 8)"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Marigold Family Dental" — a small dental practice's self-hosted
# appointment booking site. Front-desk staff can search booked appointments
# by patient last name; that search box concatenates user input directly
# into a SQL query. Injecting through it dumps a staff-login table that
# stores passwords in plaintext (a legacy decision nobody ever revisited),
# and the front-desk password was reused for the matching Linux shell
# account. A second, unrelated leftover — a nightly backup routine that
# encrypts a staff-credential blob with OpenSSL but leaves the passphrase
# sitting in a neighboring "restore notes" file — leaks a second staff
# account's password. A third, unrelated misconfiguration — a sudoers rule
# that lets a maintenance group run a diagnostics tool as root while
# keeping LD_PRELOAD in the inherited environment — completes the chain to
# root.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-cli php-mysql \
    mariadb-server \
    openssh-server \
    ufw \
    cron \
    gcc

# --- 2. Users ----------------------------------------------------------------
# Front-desk account. Weak, dictionary-crackable password — a genuine
# rockyou.txt entry — reused between the clinic's staff_users DB table
# (dumped via the SQL injection) and this shell account. This is the
# intentional bridge from web foothold to SSH.
if ! id -u front_desk >/dev/null 2>&1; then
    useradd -m -s /bin/bash front_desk
fi
echo "front_desk:butterfly1" | chpasswd

# Lab-technician account — the lateral-movement target. Its real login
# password is set here (so the decrypted credential recovered later
# actually works), but nothing points to it until the encrypted backup is
# found in Part 4. Also a genuine rockyou.txt entry.
if ! id -u labtech >/dev/null 2>&1; then
    useradd -m -s /bin/bash labtech
fi
echo "labtech:tinkerbell1" | chpasswd

# Dedicated maintenance group for the diagnostics sudoers rule (section 8)
# — membership alone doesn't grant root; the LD_PRELOAD leak does.
groupadd -f dental-ops
usermod -aG dental-ops labtech

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dr_patel >/dev/null 2>&1; then
    useradd -m -s /bin/bash dr_patel
fi
echo "dr_patel:$(openssl rand -base64 24)" | chpasswd

# --- 3. Database: staff logins + patient appointments -----------------------
systemctl enable mariadb >/dev/null 2>&1 || true
systemctl restart mariadb

mysql -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS marigold;
CREATE USER IF NOT EXISTS 'mfd_app'@'localhost' IDENTIFIED BY 'butterfly1';
GRANT ALL PRIVILEGES ON marigold.* TO 'mfd_app'@'localhost';
FLUSH PRIVILEGES;
USE marigold;

CREATE TABLE IF NOT EXISTS staff_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50),
    password VARCHAR(100),
    role VARCHAR(30)
);
INSERT INTO staff_users (username, password, role) VALUES
    ('front_desk', 'butterfly1', 'reception'),
    ('dr_patel', 'not-the-shell-password', 'dentist');

CREATE TABLE IF NOT EXISTS appointments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    patient_last_name VARCHAR(60),
    appt_date VARCHAR(20),
    dentist VARCHAR(50)
);
INSERT INTO appointments (patient_last_name, appt_date, dentist) VALUES
    ('Nguyen', '2026-09-08', 'Dr. Patel'),
    ('Okafor', '2026-09-09', 'Dr. Patel'),
    ('Ramirez', '2026-09-10', 'Dr. Patel');
SQL

# MySQL only listens on localhost by default (bind-address 127.0.0.1) —
# it is intentionally NOT exposed on the network; it is only reachable
# through the SQL injection in the web app.

# --- 4. Web application: Marigold appointment search -------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Marigold Family Dental</title></head>
<body style="font-family:sans-serif;">
<h1>Marigold Family Dental</h1>
<p>Front-desk appointment lookup.</p>
<form method="get" action="search.php">
  Patient last name: <input name="lastname">
  <input type="submit" value="Search">
</form>
</body>
</html>
EOF

# The ONE initial-access vulnerability on this box: search.php builds a
# SQL query by directly concatenating the "lastname" GET parameter into
# the WHERE clause, with no parameter binding and no input sanitization —
# a textbook UNION-based SQL injection.
cat > "${WEBROOT}/search.php" <<'EOF'
<?php
// Marigold front-desk appointment search
// TODO(front-desk contractor, unreviewed): move to prepared statements
$conn = new mysqli('localhost', 'mfd_app', 'butterfly1', 'marigold');
$lastname = $_GET['lastname'] ?? '';
$sql = "SELECT appt_date, dentist FROM appointments WHERE patient_last_name = '$lastname'";
$result = @$conn->query($sql);
echo "<h2>Appointment Search</h2>";
if ($result) {
    echo "<ul>";
    while ($row = $result->fetch_assoc()) {
        echo "<li>{$row['appt_date']} with {$row['dentist']}</li>";
    }
    echo "</ul>";
} else {
    echo "<p>Query error: " . htmlspecialchars($conn->error) . "</p>";
}
?>
EOF

chown -R www-data:www-data "${WEBROOT}"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 5. Easy flag: reachable shortly after SSH login as front_desk ---------
cat > /home/front_desk/EASY_FLAG.txt <<'EOF'
MFD{UN10N-S3L3CT-YOUR-WAY-1N}
EOF
chown front_desk:front_desk /home/front_desk/EASY_FLAG.txt
chmod 600 /home/front_desk/EASY_FLAG.txt

# --- 6. Intermediate vulnerability: encrypted credential blob whose
#         passphrase was left in a neighboring file (lateral movement,
#         distinct from the SQL injection used for initial access) --------
# A nightly backup routine "safely" encrypts a staff-credential export
# with OpenSSL before archiving it. Whoever set this up also dropped a
# plaintext "restore notes" file right next to it, for their own future
# reference, containing the exact passphrase needed to reverse it. This
# is a decrypt-with-a-leaked-key misconfiguration, not a hash to crack —
# a different primitive from offline dictionary attacks.
mkdir -p /var/backups/marigold
cat > /tmp/staff_export.csv <<'EOF'
username,password,role
labtech,tinkerbell1,lab
EOF
openssl enc -aes-256-cbc -pbkdf2 -salt \
    -pass pass:'M0lar-Backup-2026!' \
    -in /tmp/staff_export.csv \
    -out /var/backups/marigold/staff_export.csv.enc
rm -f /tmp/staff_export.csv

cat > /var/backups/marigold/restore_notes.txt <<'EOF'
Marigold backup restore notes (IT handover doc - internal only)

The nightly staff-export backup is encrypted with OpenSSL AES-256-CBC.
To restore, decrypt with the shared backup passphrase:

    openssl enc -d -aes-256-cbc -pbkdf2 -in staff_export.csv.enc \
        -out staff_export.csv -pass pass:'M0lar-Backup-2026!'

Passphrase is also written on the sticky note on the server rack, ask
Priya if it's gone missing again.
EOF

chown root:root /var/backups/marigold/staff_export.csv.enc /var/backups/marigold/restore_notes.txt
chmod 644 /var/backups/marigold/staff_export.csv.enc /var/backups/marigold/restore_notes.txt
chmod 755 /var/backups/marigold

cat > /home/labtech/INTERMEDIATE_FLAG.txt <<'EOF'
MFD{TH3-K3Y-W4S-R1GHT-N3XT-T0-TH3-L0CK}
EOF
chown labtech:labtech /home/labtech/INTERMEDIATE_FLAG.txt
chmod 600 /home/labtech/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: sudoers LD_PRELOAD leak
#         (distinct from every other primitive used in this lab set: not
#         SUID/PATH hijack, not sudo NOPASSWD/GTFOBins, not a writable
#         script/unit, not a module-path hijack, not tar-wildcard
#         injection, not a misassigned capability) -------------------------
# dental-ops staff can run a small diagnostics tool as root via sudo
# without a password, for on-demand hardware checks. Whoever wrote the
# sudoers rule added `env_keep+=LD_PRELOAD` (intending to let a
# diagnostics logging shim be preloaded) without realizing that lets ANY
# caller supply their own shared library to be loaded into the process
# before it re-execs as root — arbitrary code execution as root via the
# dynamic linker, not the sudo target binary's own logic.
cat > /usr/local/bin/dental-diag <<'EOF'
#!/usr/bin/env bash
# Marigold hardware diagnostics helper (dental-ops on-call use)
echo "Marigold Diagnostics"
echo "---------------------"
uptime
df -h /
EOF
chmod 755 /usr/local/bin/dental-diag

cat > /etc/sudoers.d/dental-ops <<'EOF'
Defaults:%dental-ops env_keep+="LD_PRELOAD"
%dental-ops ALL=(root) NOPASSWD: /usr/local/bin/dental-diag
EOF
chmod 440 /etc/sudoers.d/dental-ops

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
MFD{3NV_K33P-LD_PR3L0AD-1S-A-R00T-SH3LL}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
mkdir -p /var/log/marigold
cat > /etc/cron.d/marigold-backup <<'EOF'
0 2 * * * root echo "backup rotation heartbeat $(date)" >> /var/log/marigold/backup.log
EOF
chmod 644 /etc/cron.d/marigold-backup

# --- 10. Firewall: only expose the intended attack surface ------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable  # note: MySQL/3306 is bound to localhost only, never exposed

# --- 11. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 cron mariadb >/dev/null 2>&1 || true
systemctl restart ssh apache2 cron mariadb

cat <<'EOF'

===================================================================
 Marigold Family Dental lab target build complete (Tutorial 8).

 Exposed services: SSH (22), HTTP (80)
 MySQL (3306) is bound to localhost only — not network-exposed.
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
