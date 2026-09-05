#!/usr/bin/env bash
#
# ===========================================================================
#  setup_fernwoodradio.sh   —   Tutorial 7: Fernwood Community Radio
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, a weak/reused
#  password sourced from rockyou.txt, an insecure file-upload web
#  vulnerability, a crackable password hash leaked via a world-readable
#  backup file, and a Python module-path hijack in a root cron job on the
#  host it runs on.
#
#  RUN THIS ONLY ON:
#    - A freshly installed, throwaway Ubuntu Server VM
#    - Inside an isolated/host-only lab network (VirtualBox 192.168.56.x),
#      with NO internet-facing NIC
#    - A VM you are prepared to snapshot and destroy afterward
#
#  DO NOT run this on a production system, a cloud instance with a public
#  IP, or any host reachable from the internet. Doing so will create a
#  genuinely exploitable machine.
#
#  Intended use: authorized security training / CTF-style practice only,
#  attacked exclusively from AXCEL-BLADE-VM (Kali) on the same host-only
#  segment.
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
#  Target Information (fill in after first boot, for your own lab notes —
#  matches the "Target Information" table at the top of the paired
#  walkthrough, Fernwood_Radio_Walkthrough.md):
#
#    Lab name                  : Fernwood Community Radio
#    Target service            : Apache/PHP + MariaDB (localhost-only) + SSH
#    Target IP address         : <fill in after boot, e.g. `ip a`>
#    Attacker Kali IP address  : <your AXCEL-BLADE-VM host-only IP>
#
#  Objective: identify and exploit three intended vulnerabilities on this
#  training VM — an Easy flag via an insecure upload-filter bypass (worked
#  with Burp Suite), an Intermediate flag via offline cracking of a leaked
#  legacy credential hash, and a Hard privilege-escalation path via a
#  Python module search-path hijack in a root cron job. See the paired
#  walkthrough for the full step-by-step attack path.
# ---------------------------------------------------------------------------

echo "==================================================================="
echo " Fernwood Community Radio — Lab Target Installer (Tutorial 7)"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Fernwood Community Radio" — a small volunteer-run internet radio
# station. Its site lets DJs upload cover art for their show and lets
# listeners browse the schedule; a MySQL database backs the playlist and
# DJ roster. The cover-art uploader trusts a client-side/blacklist
# extension check, a plaintext DB config file leaks a password that a DJ
# also reused for their shell account, a retired archive-room login file
# leaks a second crackable hash, and a root cron job that syncs the
# playlist imports a Python helper module from a group-writable directory.
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
    python3

# --- 2. Users ----------------------------------------------------------------
# DJ / low-priv account. Weak, dictionary-crackable password — genuine
# rockyou.txt entry, confirmed at line 641 ("sunshine1") — reused between
# the station's MySQL account and this shell account, which is the
# intentional password-reuse bridge from web foothold to SSH.
if ! id -u djcrew >/dev/null 2>&1; then
    useradd -m -s /bin/bash djcrew
fi
echo "djcrew:sunshine1" | chpasswd

# Archive-room volunteer account — the lateral-movement target. Its real
# login password is set here (so the cracked hash recovered later
# actually works), but nothing points to it until the legacy backup file
# is found in Part 4. Password is a genuine rockyou.txt entry, confirmed
# at line 697 ("tigger1").
if ! id -u archivist >/dev/null 2>&1; then
    useradd -m -s /bin/bash archivist
fi
echo "archivist:tigger1" | chpasswd

# Dedicated group for the playlist-sync module directory (section 8) —
# this is what makes the privilege-escalation bug possible.
groupadd -f fernwood-mods
usermod -aG fernwood-mods archivist

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dj_marcus >/dev/null 2>&1; then
    useradd -m -s /bin/bash dj_marcus
fi
echo "dj_marcus:$(openssl rand -base64 24)" | chpasswd

# --- 3. Database: playlist + DJ roster ---------------------------------------
systemctl enable mariadb >/dev/null 2>&1 || true
systemctl restart mariadb

mysql -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS fernwood;
CREATE USER IF NOT EXISTS 'fernwood_app'@'localhost' IDENTIFIED BY 'sunshine1';
GRANT ALL PRIVILEGES ON fernwood.* TO 'fernwood_app'@'localhost';
FLUSH PRIVILEGES;
USE fernwood;
CREATE TABLE IF NOT EXISTS playlist (
    id INT AUTO_INCREMENT PRIMARY KEY,
    show_name VARCHAR(100),
    dj VARCHAR(50),
    slot VARCHAR(50)
);
INSERT INTO playlist (show_name, dj, slot) VALUES
    ('Sunrise Static', 'djcrew', 'Mon 07:00'),
    ('Vinyl Hour', 'dj_marcus', 'Wed 20:00'),
    ('Archive Replay', 'archivist', 'Fri 22:00');
SQL

# MySQL only listens on localhost by default (bind-address 127.0.0.1) —
# it is intentionally NOT exposed on the network; it is only reachable
# through the leaked config credentials once local access is gained.

# --- 4. Web application: Fernwood Radio schedule + cover-art uploader -------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Fernwood Community Radio</title></head>
<body style="font-family:sans-serif;">
<h1>Fernwood Community Radio</h1>
<p>Volunteer-run internet radio, broadcasting since 2019.</p>
<ul>
  <li><a href="schedule.php">This week's schedule</a></li>
  <li><a href="upload.php">DJ cover-art upload</a></li>
</ul>
</body>
</html>
EOF

cat > "${WEBROOT}/schedule.php" <<'EOF'
<?php
$conn = new mysqli('localhost', 'fernwood_app', 'sunshine1', 'fernwood');
echo "<h2>Weekly Schedule</h2><ul>";
$res = $conn->query("SELECT show_name, dj, slot FROM playlist");
while ($row = $res->fetch_assoc()) {
    echo "<li>{$row['slot']} — {$row['show_name']} (DJ {$row['dj']})</li>";
}
echo "</ul>";
?>
EOF

mkdir -p "${WEBROOT}/uploads"
chown www-data:www-data "${WEBROOT}/uploads"
chmod 755 "${WEBROOT}/uploads"

# Insecure upload: a weak blacklist that only checks a handful of obvious
# extensions (case-sensitively) and never validates the actual file
# content/MIME type, so a renamed PHP payload (e.g. "shell.phtml" or
# "shell.PHP") sails through and Apache's default handler still executes
# it. This is the box's ONE initial-access vulnerability.
cat > "${WEBROOT}/upload.php" <<'EOF'
<?php
// Fernwood cover-art uploader
// TODO(volunteer dev, unreviewed): add real MIME validation before this
// goes live station-wide.
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['coverart'])) {
    $name = $_FILES['coverart']['name'];
    $blacklist = ['php', 'php3', 'php4', 'php5'];
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    if (in_array($ext, $blacklist)) {
        $msg = "That file type isn't allowed.";
    } else {
        $dest = __DIR__ . '/uploads/' . basename($name);
        move_uploaded_file($_FILES['coverart']['tmp_name'], $dest);
        $msg = "Uploaded to uploads/" . htmlspecialchars(basename($name));
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>Fernwood - DJ Cover Art Upload</title></head>
<body style="font-family:sans-serif;">
<h1>DJ Show Cover-Art Upload</h1>
<form method="post" enctype="multipart/form-data">
  <input type="file" name="coverart">
  <input type="submit" value="Upload">
</form>
<p><?php echo $msg; ?></p>
</body>
</html>
EOF

chown -R www-data:www-data "${WEBROOT}"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 5. Leaked credential reachable from the web-shell foothold -------------
# The DB password is duplicated in a plaintext config file outside the
# web root but readable by www-data — a common real-world sloppiness
# pattern (and the same password was reused for djcrew's shell account).
mkdir -p /etc/fernwood
cat > /etc/fernwood/db.conf <<'EOF'
; Fernwood Radio site config - do not commit to git (nobody checked)
db_host = localhost
db_user = fernwood_app
db_pass = sunshine1
db_name = fernwood
; shell login for schedule updates uses the same password, ask djcrew
EOF
chown root:www-data /etc/fernwood/db.conf
chmod 640 /etc/fernwood/db.conf

# --- 6. Easy flag: reachable shortly after SSH login as djcrew -------------
cat > /home/djcrew/EASY_FLAG.txt <<'EOF'
FCR{UPL0AD-F1LT3RS-N33D-C0NT3NT-N0T-JUST-3XT3NS10NS}
EOF
chown djcrew:djcrew /home/djcrew/EASY_FLAG.txt
chmod 600 /home/djcrew/EASY_FLAG.txt

# --- 7. Intermediate vulnerability: crackable hash in a leftover legacy
#         archive-room login file (lateral movement, distinct from the
#         web upload flaw used for initial access) --------------------------
# Before the station digitized its playlist, the archive room used a
# simple Apache Basic-Auth login for the tape catalog. It was retired
# but the credential file was left behind, world-readable, in a backups
# folder. It holds a real SHA-512 crypt hash — not an encoding like
# base64/hex — so this box exercises offline hash cracking (John the
# Ripper) rather than decoding.
mkdir -p /var/backups/fernwood
ARCHIVIST_HASH=$(openssl passwd -6 -salt fernwood tigger1)
cat > /var/backups/fernwood/archive_room.htpasswd <<EOF
# legacy tape-catalog basic-auth file - retired, .htaccess removed
# TODO: delete, no longer used (never actioned)
archivist:${ARCHIVIST_HASH}
EOF
chown root:root /var/backups/fernwood/archive_room.htpasswd
chmod 644 /var/backups/fernwood/archive_room.htpasswd
chmod 755 /var/backups/fernwood

cat > /home/archivist/INTERMEDIATE_FLAG.txt <<'EOF'
FCR{CRYPT-HASH3S-G0-1N-J0HN-N0T-1N-BASE64}
EOF
chown archivist:archivist /home/archivist/INTERMEDIATE_FLAG.txt
chmod 600 /home/archivist/INTERMEDIATE_FLAG.txt

# --- 8. Privilege-escalation vulnerability: Python module-path hijack in
#         a root cron job (distinct from every other primitive used in
#         this lab set: not sudo/GTFOBins, not SUID/PATH hijack, not a
#         writable script/unit, not tar-wildcard injection) -----------------
# A root cron job (lab-speed: every minute) runs a small playlist-sync
# script that imports a helper module from a "modules" directory. That
# directory is group-writable by "fernwood-mods" so volunteers can drop
# in new helper snippets without bothering an admin — but the script
# inserts that directory at the FRONT of sys.path before importing, so
# any member of fernwood-mods can plant a malicious stationutils.py and
# have arbitrary Python code run as root the next time the job fires.
mkdir -p /opt/fernwood/modules
chown root:fernwood-mods /opt/fernwood/modules
chmod 775 /opt/fernwood/modules   # group-writable: THE bug

cat > /opt/fernwood/modules/stationutils.py <<'EOF'
# Fernwood playlist-sync helper module (legitimate stub)
def log_sync(msg):
    with open('/var/log/fernwood/sync.log', 'a') as f:
        f.write(msg + "\n")
EOF
chmod 644 /opt/fernwood/modules/stationutils.py

mkdir -p /var/log/fernwood
chmod 755 /var/log/fernwood

cat > /usr/local/sbin/fernwood_playlist_sync.py <<'EOF'
#!/usr/bin/env python3
# Fernwood nightly playlist sync (lab-speed: runs every minute)
import sys
sys.path.insert(0, '/opt/fernwood/modules')  # THE bug: writable, and first on path
import stationutils

stationutils.log_sync("playlist sync tick")
EOF
chmod 755 /usr/local/sbin/fernwood_playlist_sync.py

cat > /etc/cron.d/fernwood-playlist-sync <<'EOF'
* * * * * root /usr/bin/python3 /usr/local/sbin/fernwood_playlist_sync.py
EOF
chmod 644 /etc/cron.d/fernwood-playlist-sync

# --- 9. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
FCR{SYS-PATH-1NS3RT-Z3R0-1S-C0D3-3X3CUT10N}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 10. Harmless cron job for realism (not part of intended path) ----------
cat > /etc/cron.d/fernwood-heartbeat <<'EOF'
* * * * * root echo "fernwood heartbeat $(date)" >> /var/log/fernwood/heartbeat.log
EOF
chmod 644 /etc/cron.d/fernwood-heartbeat

# --- 11. Firewall: only expose the intended attack surface ------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable  # note: MySQL/3306 is bound to localhost only, never exposed

# --- 12. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 cron mariadb >/dev/null 2>&1 || true
systemctl restart ssh apache2 cron mariadb

cat <<'EOF'

===================================================================
 Fernwood Community Radio lab target build complete (Tutorial 7).

 Exposed services: SSH (22), HTTP (80)
 MySQL (3306) is bound to localhost only — not network-exposed.
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
