#!/usr/bin/env bash
#
# ===========================================================================
#  setup_forgeci.sh
#
#  !!! WARNING - READ BEFORE RUNNING !!!
#  This script INTENTIONALLY installs vulnerable software, weak credentials,
#  an unauthenticated admin-panel information leak, a hex-encoded SSH key
#  leaked via a world-readable state file, and a writable-systemd-unit +
#  scoped-sudo privilege-escalation flaw on the host it runs on.
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
echo " Forge CI Lab Target Installer"
echo " This will modify system accounts, services, and firewall rules."
echo " Press Ctrl+C within 10 seconds to abort."
echo "==================================================================="
sleep 10

# ---------------------------------------------------------------------------
# Theme: "Forge CI" — a fictional startup's lightweight, self-hosted CI
# runner for small dev teams. A web dashboard shows build status; a
# "temporary" debug panel was shipped without authentication and left in
# place, and it echoes a recent build log that names a fallback SSH
# account. A second, unrelated automation component (the runner agent)
# separately caches its last deploy key on disk, hex-encoded "so it isn't
# sitting around as a raw PEM file" — it is not actually protected. That
# service account belongs to a group that can edit the agent's own
# systemd unit, and holds a narrowly scoped sudo grant to restart it.
# ---------------------------------------------------------------------------

# --- 1. Base packages -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apache2 php php-cli \
    openssh-server \
    ufw \
    cron \
    xxd

# --- 2. Users ----------------------------------------------------------------
# Low-privilege CI operator account. Weak, dictionary-crackable password
# (present in the project's rockyou.txt — verified at line 995 of the
# project copy, "daniel1") — consistent with the ISEC3002 lab convention
# of using genuinely wordlist-crackable credentials.
if ! id -u cirunner >/dev/null 2>&1; then
    useradd -m -s /bin/bash cirunner
fi
echo "cirunner:daniel1" | chpasswd

# Dedicated service account for the Forge agent process. No direct
# password login by design — reached only via the leaked hex-encoded key
# in section 6.
if ! id -u forgebot >/dev/null 2>&1; then
    useradd -m -s /bin/bash -r forgebot
fi
usermod -L forgebot

# Group used to grant the agent-restart privilege + unit-file write access
# to the forgebot service account (section 7).
groupadd -f cirun-admins
usermod -aG cirun-admins forgebot

# A second, uninvolved account for realism (not part of the intended path).
if ! id -u dev_yara >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev_yara
fi
echo "dev_yara:$(openssl rand -base64 24)" | chpasswd

# --- 3. Web application: Forge CI Dashboard ----------------------------------
WEBROOT=/var/www/html
rm -f "${WEBROOT}/index.html"

cat > "${WEBROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Forge CI - Build Dashboard</title></head>
<body style="font-family:sans-serif;">
<h1>Forge CI</h1>
<p>Self-hosted CI runner for small teams. Dashboard login is being
migrated to SSO — check back soon.</p>
</body>
</html>
EOF

# Unauthenticated debug/admin panel: shipped during early development to
# let engineers eyeball the latest build without logging in, and never
# gated behind auth or removed before "launch."
mkdir -p "${WEBROOT}/admin"
cat > "${WEBROOT}/admin/status.php" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Forge CI - Debug Status Panel</title></head>
<body style="font-family:monospace; background:#111; color:#0f0;">
<h1>Forge CI :: Debug Status Panel</h1>
<p>[TEMP] No auth wired up yet - ticket FORGE-77, remove before GA.</p>
<pre>
runner: agent-01
last_build: #482 (success)
queue_depth: 0
</pre>
<h2>Latest build log tail</h2>
<pre>
[build #482] checkout complete
[build #482] running test suite... 41/41 passed
[build #482] NOTE: CI box SSH access for on-call debugging is via the
             cirunner account (fallback while SSO migration is pending)
[build #482] artifact uploaded
[build #482] done
</pre>
</body>
</html>
EOF

chown -R www-data:www-data "${WEBROOT}/admin"
chmod 755 "${WEBROOT}/admin"

systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- 4. Easy flag: reachable immediately after logging in as cirunner ------
cat > /home/cirunner/EASY_FLAG.txt <<'EOF'
FORGE{D3BUG-P4N3LS-4R3-N0T-4CC3SS-C0NTR0L}
EOF
chown cirunner:cirunner /home/cirunner/EASY_FLAG.txt
chmod 600 /home/cirunner/EASY_FLAG.txt

# --- 5. Runner agent + artifact store (background realism) ------------------
mkdir -p /var/lib/forge/artifacts/build-482
cat > /var/lib/forge/artifacts/build-482/manifest.json <<'EOF'
{"build": 482, "status": "success", "tests_passed": 41, "tests_total": 41}
EOF
chown -R forgebot:forgebot /var/lib/forge/artifacts
chmod -R 750 /var/lib/forge/artifacts

# --- 6. Intermediate vulnerability: hex-encoded SSH key in a world-readable
#         agent state file (lateral movement, distinct from the web-panel
#         leak used for initial access) -----------------------------------
# The Forge agent caches its own deploy key locally so it can survive a
# credential-store outage. Whoever built this "temporarily" hex-encoded
# the raw private key into a state file instead of using the system
# keyring, reasoning it "isn't plaintext" - it is, once decoded, and the
# file was left world-readable at the systemd-unit-adjacent default.
mkdir -p /var/lib/forge/state
ssh-keygen -t ed25519 -N "" -f /tmp/forgebot_key -C "forgebot@forge-ci" -q
mkdir -p /home/forgebot/.ssh
cp /tmp/forgebot_key.pub /home/forgebot/.ssh/authorized_keys
chown -R forgebot:forgebot /home/forgebot/.ssh
chmod 700 /home/forgebot/.ssh
chmod 600 /home/forgebot/.ssh/authorized_keys

xxd -p /tmp/forgebot_key | tr -d '\n' > /var/lib/forge/state/deploy_key.hex
echo >> /var/lib/forge/state/deploy_key.hex
rm -f /tmp/forgebot_key /tmp/forgebot_key.pub

cat > /var/lib/forge/state/README.txt <<'EOF'
Forge Agent local state cache
------------------------------
deploy_key.hex - cached agent deploy key (hex, not plaintext PEM, so this
                  is fine to leave world-readable for now - revisit once
                  the credential-store integration ships. ticket FORGE-104)
EOF

chown root:root /var/lib/forge/state
chmod 755 /var/lib/forge/state
chmod 644 /var/lib/forge/state/deploy_key.hex /var/lib/forge/state/README.txt

cat > /home/forgebot/INTERMEDIATE_FLAG.txt <<'EOF'
FORGE{H3X-1S-4-F0RM4T-N0T-4-PR0T3CT10N}
EOF
chown forgebot:forgebot /home/forgebot/INTERMEDIATE_FLAG.txt
chmod 600 /home/forgebot/INTERMEDIATE_FLAG.txt

# --- 7. Privilege-escalation vulnerability: writable systemd unit + scoped
#         sudo restart (distinct from sudo/GTFOBins, SUID/PATH-hijack,
#         group-writable cron, and cap_setuid primitives used elsewhere in
#         this lab set) ----------------------------------------------------
# The forge-agent service is meant to be tunable by on-call engineers
# without paging the platform team, so its unit file is group-writable by
# cirun-admins, and that group also holds a narrowly scoped NOPASSWD sudo
# grant limited to restarting *this one unit*. Nobody realized that
# controlling ExecStart on a unit you can also restart as root is a full
# root primitive - the sudo rule was written to feel "safe" because it
# doesn't grant a shell directly.
cat > /usr/local/bin/forge-agent-run.sh <<'EOF'
#!/usr/bin/env bash
echo "$(date '+%F %T') forge-agent heartbeat - polling for jobs" >> /var/log/forge-agent.log
sleep 30
EOF
chmod 755 /usr/local/bin/forge-agent-run.sh

cat > /etc/systemd/system/forge-agent.service <<'EOF'
[Unit]
Description=Forge CI runner agent

[Service]
Type=simple
ExecStart=/usr/local/bin/forge-agent-run.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
chown root:cirun-admins /etc/systemd/system/forge-agent.service
chmod 664 /etc/systemd/system/forge-agent.service   # group-writable: THE bug

touch /var/log/forge-agent.log
chmod 644 /var/log/forge-agent.log

systemctl daemon-reload
systemctl enable --now forge-agent.service >/dev/null 2>&1 || true

cat > /etc/sudoers.d/forgeci <<'EOF'
%cirun-admins ALL=(root) NOPASSWD: /usr/bin/systemctl restart forge-agent.service, /usr/bin/systemctl daemon-reload
EOF
chmod 440 /etc/sudoers.d/forgeci

# --- 8. Root flag -------------------------------------------------------------
mkdir -p /root
cat > /root/HARD_FLAG.txt <<'EOF'
FORGE{WR1T4BL3-UN1T-PLUS-SC0P3D-SUD0-1S-ST1LL-R00T}
EOF
chmod 600 /root/HARD_FLAG.txt

# --- 9. Harmless cron job for realism (not part of intended path) -----------
cat > /etc/cron.d/forgeci-heartbeat <<'EOF'
* * * * * root echo "forge ci heartbeat $(date)" >> /var/log/forgeci-heartbeat.log
EOF
chmod 644 /etc/cron.d/forgeci-heartbeat

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
 Forge CI lab target build complete.

 Exposed services: SSH (22), HTTP (80)
 This machine is INTENTIONALLY VULNERABLE.
 Keep it isolated. Snapshot it now if you want a clean restore point.
===================================================================
EOF
