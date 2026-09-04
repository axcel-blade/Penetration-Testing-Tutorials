[← Back to Index](00-index.md) | [← Previous: Set Up for Penetration Testing](07-pentest-setup.md)

# Part 8: Networking Your Pentest Lab

- Keep your pentest VM's network adapter on **NAT** or a **Host-Only/Internal Network** when practicing against intentionally vulnerable targets (see below), so traffic never touches your real LAN.
- Only switch to **Bridged** networking when testing devices on a network you own or have written authorization to test.

## Practice Targets (legal, intentionally vulnerable)

Set up a second VM as a safe target to practice against:
- **Metasploitable 2/3** — deliberately vulnerable Linux VM: https://sourceforge.net/projects/metasploitable/
- **OWASP Juice Shop** — vulnerable web app (Docker container)
- **DVWA (Damn Vulnerable Web Application)**
- **TryHackMe / HackTheBox** — legal online labs with their own VPN-connected targets

Put your pentest VM and target VM(s) on the same **Internal Network** or **Host-Only Adapter** in VirtualBox so they can reach each other without touching the internet or your real network.

## Step-by-Step: Placing Kali/Pentest VM and Target VM on the Same Isolated Network

1. **Shut down both VMs** (the Kali/pentest VM and the target VM, e.g. Metasploitable) before changing network settings.

2. **Choose a network type:**
   - **Internal Network** — fully isolated; VMs can only talk to each other, no internet access at all. Best for pure attack-practice labs.
   - **Host-Only Adapter** — VMs can talk to each other *and* to your host machine, still no internet. Useful if you want to manage the target from your host too.

3. **Configure the Kali/pentest VM:**
   - Select the VM → **Settings → Network**.
   - Adapter 1 → Attached to: **Internal Network** (or **Host-Only Adapter**).
   - Name the network, e.g. `pentestlab` (must match exactly on the target VM).
   - If you still want internet access on Kali for updates/tool downloads, enable a second adapter:
     - Adapter 2 → Attached to: **NAT**, and enable it (checkbox "Enable Network Adapter").

4. **Configure the target VM (e.g., Metasploitable):**
   - Select the VM → **Settings → Network**.
   - Adapter 1 → Attached to: **Internal Network** (or **Host-Only Adapter**).
   - Name: same as Kali's, e.g. `pentestlab`.
   - Leave any other adapters disabled — you generally don't want a deliberately vulnerable VM reachable from the internet.

5. **If using Host-Only Adapter and none exists yet:**
   - VirtualBox menu → **File → Host Network Manager** (or **Tools → Network** in newer versions) → **Create** to add a Host-Only network (e.g. `vboxnet0`) with a DHCP server enabled, or set a static range manually.

6. **Boot both VMs** and verify connectivity:
   - Find each VM's IP:
     ```bash
     ip a
     ```
   - From Kali, ping the target:
     ```bash
     ping <target-internal-ip>
     ```
   - Run a test scan:
     ```bash
     nmap -sV <target-internal-ip>
     ```
     - `-sV`: probe open ports to detect service/version info, confirming the target is reachable and responding
   - If ping/scan succeeds, both machines are correctly isolated together on the same lab network.

7. **Double-check isolation:** from the target VM, confirm it has no route to the internet (this protects you from accidentally exposing a vulnerable machine):
   ```bash
   ping -c 2 8.8.8.8
   ```
   - `-c 2`: send only 2 ping packets and stop, instead of pinging forever
   
   This should fail (timeout) if the target only has an Internal/Host-Only adapter, as intended.

---

Next: [Troubleshooting: Drag & Drop Error →](09-troubleshooting-dnd.md)
