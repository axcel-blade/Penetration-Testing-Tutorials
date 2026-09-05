#!/usr/bin/env bash
#
# ===========================================================================
#  setup_harborview.sh   —   Tutorial 10: Harborview Boutique Hotel
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, an unrestricted
#  file-upload RCE in a staff ID-photo uploader, a weak/reused password
#  sourced from rockyou.txt, a guest-accessible Samba share exposing a
#  password-protected archive, and a mistakenly SUID-root Python
#  interpreter that yields a root shell, on the host it runs on.
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
#  Intended use: authorized security training / CTF-style practice only,
#  worked with Metasploit (msfconsole/msfvenom) from the paired
#  walkthrough.
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
#  Target Information (fill in after first boot, for your own lab notes —
#  matches the "Target Information" table at the top of the paired
#  walkthrough, Harborview_Hotel_Walkthrough.md):
#
#    Lab name                  : Harborview Boutique Hotel
#    Target service            : Apache/PHP + Samba + SSH
#    Target IP address         : <fill in after boot, e.g. `ip a`>
#    Attacker Kali IP address  : <your attacker VM's isolated-network IP>
#
#  Objective: identify and exploit three intended vulnerabilities on this
#  training VM, worked through Metasploit — an Easy flag via an
#  msfvenom-generated PHP meterpreter payload uploaded through an
#  unrestricted file-upload endpoint, an Intermediate flag via cracking a
#  password-protected archive found on a guest-accessible Samba share, and
#  a Hard privilege-escalation path via a mistakenly SUID-root Python
#  interpreter. See the paired walkthrough for the full step-by-step
#  attack path.
# ---------------------------------------------------------------------------

echo "==================================================================="
echo " Harborview Boutique Hotel — Lab Target Installer (Tutorial 10)"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Harborview Boutique Hotel" — a small independent hotel's
# self-hosted staff back-office portal. Front-desk staff upload an ID
# photo when they're onboarded; the uploader was thrown together quickly
# and accepts any file with no extension or content checks at all, so a
# PHP payload uploaded as-is gives code execution the moment it's
# requested. That foothold reveals a plaintext front-desk shell
# credential in the portal's config. A second, unrelated leftover — a
# guest-accessible Samba share used to hand files back and forth with a
# payroll contractor — still has an old password-protected backup archive
# sitting on it. A third, unrelated mistake — a housekeeping-scheduling
# script's author left the system Python 3 interpreter SUID-root after a
# debugging session and never noticed — completes the chain to root.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-cli \
    samba \
    openssh-server \
    ufw \
    cron \
    zip

# --- 2. Users ----------------------------------------------------------------
# Front-desk account. Weak, dictionary-crackable password — a genuine
# rockyou.txt entry — set here as the account's real login password so
# the credential recovered from the uploader's config in Part 3 actually
# works.
if ! id -u frontdesk >/dev/null 2>&1; then
    useradd -m -s /bin/bash frontdesk
fi
echo "frontdesk:iloveyou1" | chpasswd

# Housekeeping-scheduling account — the lateral-movement target. Its real
# login password is set here (so the credential recovered from the
# cracked Samba archive in Part 4 actually works), but nothing points to
# it until that archive is found and cracked.
if ! id -u housekeeping >/dev/null 2>&1; then
    useradd -m -s /bin/bash housekeeping
fi
echo "housekeeping:poohbear1" | chpasswd

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u mgr_owens >/dev/null 2>&1; then
    useradd -m -s /bin/bash mgr_owens
fi
echo "mgr_owens:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: Harborview staff ID-photo uploader ------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Harborview Boutique Hotel - Staff Portal</title></head>
<body style="font-family:sans-serif;">
<h1>Harborview Boutique Hotel</h1>
<p>Staff onboarding: upload your ID photo below.</p>
<form method="post" enctype="multipart/form-data" action="upload.php">
  <input type="file" name="idphoto">
  <input type="submit" value="Upload">
</form>
</body>
</html>
EOF

mkdir -p "${WEBROOT}/uploads"

# The ONE initial-access vulnerability on this box: upload.php performs
# NO extension check, NO MIME check, and NO content inspection at all —
# it saves whatever is posted, under its original filename, directly into
# a web-servable directory. Any uploaded PHP file executes immediately
# when requested.
cat > "${WEBROOT}/upload.php" <<'EOF'
<?php
// Harborview staff ID-photo uploader
// TODO(seasonal hire, unreviewed): add file-type validation before go-live
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['idphoto'])) {
    $dest = __DIR__ . '/uploads/' . basename($_FILES['idphoto']['name']);
    move_uploaded_file($_FILES['idphoto']['tmp_name'], $dest);
    $msg = "Uploaded to uploads/" . htmlspecialchars(basename($_FILES['idphoto']['name']));
}
?>
<!DOCTYPE html>
<html>
<head><title>Harborview - Upload Result</title></head>
<body style="font-family:sans-serif;">
<p><?php echo $msg ?: "No file received."; ?></p>
<p><a href="index.php">Back</a></p>
</body>
</html>
EOF

# Config file the uploader's onboarding workflow also reads from, leaked
# to www-data's reach the same way as the app code itself — a plaintext
# front-desk shell credential dropped next to the app instead of using a
# secrets manager.
cat > "${WEBROOT}/staff_config.php" <<'EOF'
<?php
// Harborview staff portal config - internal use only
// front-desk shell account for onboarding scripts:
$FRONTDESK_USER = "frontdesk";
$FRONTDESK_PASS = "iloveyou1";
?>
EOF
chmod 644 "${WEBROOT}/staff_config.php"

chown -R www-data:www-data "${WEBROOT}"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 4. Easy flag: reachable shortly after SSH login as frontdesk ----------
cat > /home/frontdesk/EASY_FLAG.txt <<'EOF'
HBH{UNR3STR1CT3D-UPL0ADS-ARE-FR33-RC3}
EOF
chown frontdesk:frontdesk /home/frontdesk/EASY_FLAG.txt
chmod 600 /home/frontdesk/EASY_FLAG.txt

# --- 5. Intermediate vulnerability: guest-accessible Samba share with a
#         password-protected backup archive (lateral movement, distinct
#         from the file-upload vulnerability used for initial access) -----
# A Samba share was set up years ago so front-desk staff could hand
# scheduling files back and forth with an outside payroll contractor.
# Guest access was left on "temporarily" and never revisited. An old
# payroll backup archive still sits on it, password-protected — the
# archive password itself is a genuine rockyou.txt entry, so this
# exercises offline zip-password cracking (fcrackzip/John) rather than
# hash cracking or simple decoding.
mkdir -p /srv/samba/backoffice
echo "housekeeping,poohbear1" > /tmp/payroll_notes.csv
zip -j -P 'letmein1' /srv/samba/backoffice/payroll_backup.zip /tmp/payroll_notes.csv >/dev/null
rm -f /tmp/payroll_notes.csv
chmod 644 /srv/samba/backoffice/payroll_backup.zip
chown -R root:root /srv/samba/backoffice
chmod 755 /srv/samba/backoffice

cat >> /etc/samba/smb.conf <<'EOF'

[backoffice]
   path = /srv/samba/backoffice
   browseable = yes
   read only = yes
   guest ok = yes
   guest only = yes
EOF
systemctl restart smbd nmbd

cat > /home/housekeeping/INTERMEDIATE_FLAG.txt <<'EOF'
HBH{GU3ST-SHAR3S-ST1LL-N33D-A-CL3ANUP}
EOF
chown housekeeping:housekeeping /home/housekeeping/INTERMEDIATE_FLAG.txt
chmod 600 /home/housekeeping/INTERMEDIATE_FLAG.txt

# --- 6. Privilege-escalation vulnerability: SUID-root Python interpreter
#         (distinct from every other primitive used in this lab set: not
#         a custom SUID/PATH-hijack helper, not sudo NOPASSWD/GTFOBins,
#         not a writable script/unit, not a module-path hijack, not
#         tar-wildcard injection, not a misassigned capability, not an
#         LD_PRELOAD sudoers leak, not docker-group abuse) -----------------
# While debugging a slow housekeeping-scheduling cron job, an admin ran
# `chmod u+s /usr/bin/python3.*` to rule out a permissions issue, got
# distracted, and never undid it. The *stock* interpreter binary itself
# is now SUID-root — a classic, entirely real-world GTFOBins scenario
# (https://gtfobins.github.io/gtfobins/python/#suid) requiring no custom
# helper binary or PATH manipulation at all.
PYBIN=$(readlink -f "$(command -v python3)")
chmod u+s "${PYBIN}"

# --- 7. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
HBH{A-STR4Y-CHM0D-U+S-1S-ALL-1T-TAK3S}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 8. Harmless cron job for realism (not part of intended path) -----------
mkdir -p /var/log/harborview
cat > /etc/cron.d/harborview-housekeeping <<'EOF'
* * * * * root echo "housekeeping schedule heartbeat $(date)" >> /var/log/harborview/heartbeat.log
EOF
chmod 644 /etc/cron.d/harborview-housekeeping

# --- 9. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 139/tcp   # Samba (NetBIOS session)
ufw allow 445/tcp   # Samba (SMB over TCP)
ufw --force enable

# --- 10. Final banner ---------------------------------------------------------
systemctl enable ssh apache2 cron smbd nmbd >/dev/null 2>&1 || true
systemctl restart ssh apache2 cron smbd nmbd

cat <<'EOF'

===================================================================
 Harborview Boutique Hotel lab target build complete (Tutorial 10).

 Exposed services: SSH (22), HTTP (80), Samba (139/445, guest share only)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
