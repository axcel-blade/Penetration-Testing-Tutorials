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

Put your pentest VM and target VM(s) on the same **Host-Only Adapter** in VirtualBox so they can reach each other (and your host) without exposing the lab to your real LAN, while still giving each VM a separate NAT adapter for internet access (OS updates, tool downloads).

## Step-by-Step: Placing Kali/Pentest VM and Target VM on the Same Isolated Network

1. **Shut down both VMs** (the Kali/pentest VM and the target VM, e.g. Metasploitable) before changing network settings.

2. **Adapter scheme used here (both VMs):**
   - **Adapter 1 → NAT** — gives the VM outbound internet access (updates, package installs) without exposing it to inbound connections from your LAN.
   - **Adapter 2 → Host-Only Adapter** — the actual lab network; both VMs sit on the same Host-Only network so they can reach each other and your host, isolated from the internet and your real LAN.

3. **Configure the Kali/pentest VM:**
   - Select the VM → **Settings → Network**.
   - Adapter 1 → Attached to: **NAT**, enabled.
   - Adapter 2 → Attached to: **Host-Only Adapter**, enabled. Select the same Host-Only network (e.g. `vboxnet0`) you'll use on the target VM.

4. **Configure the target VM (e.g., Metasploitable):**
   - Select the VM → **Settings → Network**.
   - Adapter 1 → Attached to: **NAT**, enabled.
   - Adapter 2 → Attached to: **Host-Only Adapter**, enabled. Select the same Host-Only network as Kali's Adapter 2.
   - Leave any other adapters disabled.

5. **If the Host-Only network doesn't exist yet:**
   - VirtualBox menu → **File → Host Network Manager** (or **Tools → Network** in newer versions) → **Create** to add a Host-Only network (e.g. `vboxnet0`) with a DHCP server enabled, or set a static range manually.

6. **Boot both VMs** and verify connectivity:
   - Find each VM's IPs — you'll see two, one per adapter:
     ```bash
     ip a
     ```
   - Note the address on the Host-Only adapter (typically `enp0s8`/`eth1`, in the same subnet as your Host-Only network, e.g. `192.168.56.0/24`) — that's the one to use for lab traffic, not the NAT adapter's address.
   - From Kali, ping the target on its Host-Only IP:
     ```bash
     ping <target-hostonly-ip>
     ```
   - Run a test scan:
     ```bash
     nmap -sV <target-hostonly-ip>
     ```
   - If ping/scan succeeds over the Host-Only IPs, both machines are correctly reachable on the same lab network.

7. **Double-check the target isn't reachable from your real LAN:** the target's NAT adapter (Adapter 1) gives it outbound internet access by design, but VirtualBox NAT does not accept inbound connections from your LAN or expose the VM to other devices on your network. Confirm no other device on your LAN can reach the target's services (e.g. from another machine, `nmap -p 21,22,80 <target-hostonly-ip>` should simply fail to route, since that IP only exists on the Host-Only network). If you need the target reachable from elsewhere on purpose, that's a deliberate choice — not the default here.

---

Next: [Troubleshooting: Drag & Drop Error →](09-troubleshooting-dnd.md)
