#!/usr/bin/env bash
#
# ===========================================================================
#  setup_nimbushome.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, weak credentials,
#  an exposed-backup web misconfiguration, a world-readable systemd unit
#  that leaks a second account's credential, and a Linux file-capability
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
echo " Nimbus Home Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Nimbus Home" — a fictional smart-home-hub startup. Their web
# dashboard lets customers view paired devices; a nightly ops job pushes a
# config backup into the web root "temporarily" during a migration and it
# was never removed. A second, unrelated ops job (firmware sync) leaks a
# service account credential through a world-readable systemd unit, and
# that service account was granted a Linux capability on a diagnostics
# helper that lets it hand out root outright.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-sqlite3 php-cli \
    sqlite3 \
    openssh-server \
    ufw \
    cron \
    gcc \
    libcap2-bin

# --- 2. Users ----------------------------------------------------------------
# Low-privilege support account used by the (fictional) Nimbus Home field
# technicians. Weak, dictionary-crackable password present in the project's
# rockyou.txt wordlist (verified at line 219 of the project copy) —
# consistent with the ISEC3002 lab convention of using genuinely
# wordlist-crackable credentials.
if ! id -u hubtech >/dev/null 2>&1; then
    useradd -m -s /bin/bash hubtech
fi
echo "hubtech:babygirl1" | chpasswd

# Dedicated service account for the firmware-sync job. No direct password
# login by design — reached only via the leaked credential in section 6.
if ! id -u svc_sync >/dev/null 2>&1; then
    useradd -m -s /bin/bash -r svc_sync
fi
usermod -L svc_sync

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dev_mateo >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_mateo
fi
echo "dev_mateo:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: Nimbus Home Dashboard -------------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Nimbus Home - Device Dashboard</title></head>
<body style="font-family:sans-serif;">
<h1>Nimbus Home</h1>
<p>Smart-hub dashboard is being migrated to the new device-status service.
Existing customers should continue using the mobile app in the meantime.</p>
</body>
</html>
EOF

cat > "${WEBROOT}/devices.php" <<'EOF'
<?php
// Nimbus Home Dashboard - device status page (stub)
// Backed by /opt/nimbus/hub.db during normal operation.
echo "Device status service temporarily unavailable during migration.";
?>
EOF

# --- 4. Initial-access vulnerability: exposed backup directory --------------
# During the dashboard migration, ops pushed a full config backup into the
# web root "just for a day or two" so a colleague could grab it remotely,
# then forgot about it. The archive contains the hub's local SQLite DB and
# a deploy note with the field-technician SSH fallback credential.
mkdir -p "${WEBROOT}/backups"

mkdir -p /tmp/nimbus_backup_stage/nimbus-hub-backup
cat > /tmp/nimbus_backup_stage/nimbus-hub-backup/DEPLOY_NOTES.txt <<'EOF'
Nimbus Home - dashboard migration notes (temporary, remove before Friday)
---------------------------------------------------------------------
- Old dashboard DB dumped below for the new team to reference schema.
- Field techs still use direct SSH for on-site diagnostics during the
  migration window. Fallback account if the provisioning VPN is down:
    user: hubtech
    pass: babygirl1
- Firmware-sync automation is unaffected by this migration; that job's
  own credentials are managed separately by the platform team.
EOF

mkdir -p /tmp/nimbus_backup_stage/nimbus-hub-backup/db
sqlite3 /tmp/nimbus_backup_stage/nimbus-hub-backup/db/hub.db <<'EOF'
CREATE TABLE devices (id INTEGER PRIMARY KEY, name TEXT, room TEXT, online INTEGER);
INSERT INTO devices (name, room, online) VALUES
    ('Thermostat', 'Living Room', 1),
    ('Porch Camera', 'Front Door', 1),
    ('Smart Plug', 'Kitchen', 0);
EOF

tar -czf "${WEBROOT}/backups/nimbus-hub-backup.tar.gz" \
    -C /tmp/nimbus_backup_stage nimbus-hub-backup
rm -rf /tmp/nimbus_backup_stage

chown -R www-data:www-data "${WEBROOT}/backups"
chmod 755 "${WEBROOT}/backups"
chmod 644 "${WEBROOT}/backups/nimbus-hub-backup.tar.gz"
# Directory listing is intentionally left on for /backups/ so the archive
# is trivially discoverable once the path is found.
a2enmod rewrite >/dev/null
cat > /etc/apache2/conf-available/nimbushome.conf <<'EOF'
<Directory /var/www/html/backups>
    Options +Indexes
    Require all granted
</Directory>
EOF
a2enconf nimbushome >/dev/null
systemctl restart apache2

# --- 5. Easy flag: reachable immediately after logging in as hubtech -------
cat > /home/hubtech/EASY_FLAG.txt <<'EOF'
NIM{M1GR4T10N-B4CKUPS-D0NT-B3L0NG-1N-W3BR00T}
EOF
chown hubtech:hubtech /home/hubtech/EASY_FLAG.txt
chmod 600 /home/hubtech/EASY_FLAG.txt

# --- 6. Intermediate vulnerability: credential leaked via a world-readable
#         systemd unit (lateral movement, distinct from the web backup) ----
# A "firmware sync" job pulls device firmware updates on a timer. The unit
# file and the script it runs are both world-readable (systemd units under
# /etc/systemd/system are 644 by default and nobody tightened this one),
# and the script itself has a fallback credential for svc_sync, base64
# "encoded for tidiness" by whoever wrote it.
mkdir -p /opt/nimbus
cat > /opt/nimbus/device_sync.sh <<'EOF'
#!/usr/bin/env bash
# Nimbus Home - firmware sync job
# Pulls the latest firmware manifests for paired devices.
#
# Fallback credential for manual sync runs if the scheduler user's keytab
# expires (left in place after the account-rotation project stalled,
# ticket NIM-118). Not "real" plaintext, just base64:
#   user: svc_sync
#   pass: c3luY2h1Yjk5
#
echo "$(date '+%F %T') firmware sync check - no updates pending" >> /var/log/nimbus-sync.log
EOF
chmod 755 /opt/nimbus/device_sync.sh

touch /var/log/nimbus-sync.log
chmod 644 /var/log/nimbus-sync.log

cat > /etc/systemd/system/device-sync.service <<'EOF'
[Unit]
Description=Nimbus Home firmware sync job

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/nimbus/device_sync.sh
EOF

cat > /etc/systemd/system/device-sync.timer <<'EOF'
[Unit]
Description=Run Nimbus Home firmware sync every minute (lab-speed; prod runs hourly)

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF
chmod 644 /etc/systemd/system/device-sync.service /etc/systemd/system/device-sync.timer
systemctl daemon-reload
systemctl enable --now device-sync.timer >/dev/null 2>&1 || true

# Actually set svc_sync's real login password to match the leaked base64
# value above (c3luY2h1Yjk5 -> "synchub99"), and give it its own shell so
# `su svc_sync` genuinely works once the credential is decoded.
usermod -U svc_sync >/dev/null 2>&1 || true
usermod -s /bin/bash svc_sync
echo "svc_sync:synchub99" | chpasswd

cat > /home/svc_sync/INTERMEDIATE_FLAG.txt <<'EOF'
NIM{W0RLD-R34D4BL3-UN1TS-L34K-CR3D3NT14LS-T00}
EOF
chown svc_sync:svc_sync /home/svc_sync/INTERMEDIATE_FLAG.txt
chmod 600 /home/svc_sync/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: Linux capability on a helper --
# svc_sync can run a small diagnostics helper that platform engineers gave
# a raw setuid CAPABILITY (cap_setuid+ep) instead of the SUID bit, so it
# could "reset its own uid to itself for logging" -- in practice, any
# capability that includes cap_setuid lets the holder call setuid(0) and
# hand back a root shell. This is a distinct escalation primitive from
# sudo NOPASSWD, a SUID/PATH-hijack binary, or a group-writable cron
# script: it lives in extended file attributes (`getcap`), not permission
# bits or sudoers.
cat > /tmp/nimbus_diag.c <<'EOF'
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>

/* "Diagnostics" helper -- originally meant to re-assert svc_sync's own
 * uid after a buggy PAM module briefly dropped it mid-session. Whoever
 * wrote it reached for setuid(0) "to be safe" and the binary was given
 * cap_setuid+ep so it didn't need the full SUID-root bit. That is still
 * enough: a process holding CAP_SETUID can call setuid(0) regardless of
 * its real UID, so this "harmless" helper hands out a root shell to
 * anyone who can execute it. */
int main() {
    printf("Nimbus diagnostics helper - resetting session UID...\n");
    if (setuid(0) != 0) {
        perror("setuid");
        return 1;
    }
    execl("/bin/bash", "bash", "-p", (char *)NULL);
    perror("execl");
    return 1;
}
EOF
gcc -o /usr/local/bin/nimbus-diag /tmp/nimbus_diag.c
chown root:root /usr/local/bin/nimbus-diag
chmod 755 /usr/local/bin/nimbus-diag
setcap cap_setuid+ep /usr/local/bin/nimbus-diag
rm -f /tmp/nimbus_diag.c

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
NIM{CAP_SETU1D-1S-R00T-W1TH0UT-A-SU1D-B1T}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
cat > /etc/cron.d/nimbus-heartbeat <<'EOF'
* * * * * root echo "hub heartbeat $(date)" >> /var/log/nimbus-heartbeat.log
EOF
chmod 644 /etc/cron.d/nimbus-heartbeat

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
 Nimbus Home lab target build complete.

 Exposed services: SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
