#!/usr/bin/env bash
#
# ===========================================================================
#  setup_elmridge.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, an unrestricted
#  file-upload web vulnerability, a world-readable cron script leaking a
#  weak "temporary" credential, and a group-writable root cron script
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
echo " Elmridge Community Library Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Elmridge Community Library" — a public library runs a small
# self-hosted catalog + Inter-Library Loan (ILL) request portal. Patrons
# can request a title from a partner branch and upload a scan of their
# library card as proof of membership. A junior contractor wired the
# upload handler to trust the browser-supplied MIME type instead of the
# actual file contents/extension.
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
# Front-desk circulation clerk account. Not reachable directly over SSH by
# design (this box's initial foothold is the web upload flaw); the clerk's
# weak password is instead recovered mid-chain from a leaked cron note,
# consistent with the ISEC3002 lab convention of using genuinely
# wordlist-crackable credentials (present in rockyou.txt).
if ! id -u libclerk >/dev/null 2>&1; then
    useradd -m -s /bin/bash libclerk
fi
echo "libclerk:reading" | chpasswd

# Dedicated group used by the ILL nightly-sync cron job (see section 6/7).
groupadd -f syslib
usermod -aG syslib libclerk

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dev_priya >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_priya
fi
echo "dev_priya:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: Elmridge Catalog & ILL Portal -----------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Elmridge Community Library - Catalog &amp; ILL Portal</title></head>
<body style="font-family:sans-serif;">
<h1>Elmridge Community Library</h1>
<p>Search the catalog, or submit an Inter-Library Loan (ILL) request
below. New patrons must attach a scan of their library card.</p>
<p><a href="ill_request.php">Submit an ILL request</a></p>
</body>
</html>
EOF

mkdir -p "${WEBROOT}/ill_uploads"

cat > "${WEBROOT}/ill_request.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>ILL Request - Elmridge Community Library</title></head>
<body style="font-family:sans-serif;">
<h1>Inter-Library Loan Request</h1>
<?php
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['card_scan'])) {
    $f = $_FILES['card_scan'];
    // NOTE(contractor, temp fix - ticket LIB-241): only checking the
    // browser-supplied MIME type for now, real content-type sniffing is
    // on the backlog for next sprint.
    $allowed = ['image/jpeg', 'image/png', 'image/gif'];
    if (in_array($f['type'], $allowed, true)) {
        $dest = __DIR__ . '/ill_uploads/' . basename($f['name']);
        move_uploaded_file($f['tmp_name'], $dest);
        echo "<p>Thanks! Your card scan was received.</p>";
    } else {
        echo "<p>Unsupported file type. Please upload a JPG, PNG, or GIF.</p>";
    }
}
?>
<form method="post" enctype="multipart/form-data">
  Library card scan: <input type="file" name="card_scan"><br>
  <input type="submit" value="Submit request">
</form>
</body>
</html>
EOF

chown -R www-data:www-data "${WEBROOT}/ill_uploads"
chmod 755 "${WEBROOT}/ill_uploads"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 4. Easy flag: reachable as www-data shortly after the upload lands ----
# Not web-accessible directly (outside the docroot) — the point is that
# basic enumeration plus the upload RCE gets you a shell fast, and the
# first flag is sitting right there once you have one.
mkdir -p /var/backups/library
cat > /var/backups/library/EASY_FLAG.txt <<'EOF'
ELM{UNR3STR1CT3D-UPL0AD-1S-N0T-VAL1D4T10N}
EOF
chown www-data:www-data /var/backups/library/EASY_FLAG.txt
chmod 640 /var/backups/library/EASY_FLAG.txt
chmod 750 /var/backups/library

# --- 5. Nightly ILL sync cron job (root) ------------------------------------
# A legitimate-looking maintenance script that "syncs" ILL requests to a
# (fictional) partner-branch mailbox. It runs as root via cron every
# minute for lab-testing speed (a real deployment would run nightly).
# The script is group-owned by "syslib" and made group-writable so the
# circulation-desk staff can tweak the sync window without bothering IT
# — this is the privilege-escalation flaw (section 7 makes it exploitable
# by anyone in that group, e.g. libclerk after landing there in Part 4).
mkdir -p /opt/library
cat > /opt/library/ill_sync.sh <<'EOF'
#!/usr/bin/env bash
# Elmridge Library - ILL nightly sync
# Pushes today's ILL requests to the partner-branch relay mailbox.
#
# Temporary fallback account for manual sync runs if the relay is down
# (contractor left this note during the outage on migration weekend -
# should have been rotated out afterward, ticket LIB-247):
#   user: libclerk
#   pass (base32, so it's not sitting around in plaintext): OJSWCZDJNZTQ====
#
echo "$(date '+%F %T') ILL sync check - no pending requests" >> /var/log/library-sync.log
EOF
chown root:syslib /opt/library/ill_sync.sh
chmod 664 /opt/library/ill_sync.sh   # group-writable: THE bug (section 7)
chmod 755 /opt/library

touch /var/log/library-sync.log
chmod 644 /var/log/library-sync.log

cat > /etc/cron.d/library-sync <<'EOF'
* * * * * root /bin/bash /opt/library/ill_sync.sh
EOF
chmod 644 /etc/cron.d/library-sync   # world-readable: leaks the note above

# --- 6. Intermediate flag: reached after decoding the cron note and su'ing -
cat > /home/libclerk/INTERMEDIATE_FLAG.txt <<'EOF'
ELM{B4S3-32-1S-3NC0D1NG-N0T-ENCRYPT10N}
EOF
chown libclerk:libclerk /home/libclerk/INTERMEDIATE_FLAG.txt
chmod 600 /home/libclerk/INTERMEDIATE_FLAG.txt

# --- 7. Root flag ------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
ELM{GR0UP-WR1T4BL3-R00T-CR0N-1S-R00T-1N-60-S3C0NDS}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 8. Firewall: only expose the intended attack surface -------------------
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw --force enable

# --- 9. Final banner ---------------------------------------------------------
systemctl enable ssh cron >/dev/null 2>&1 || true
systemctl restart ssh cron

cat <<'EOF'

===================================================================
 Elmridge Community Library lab target build complete.

 Exposed services: SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
