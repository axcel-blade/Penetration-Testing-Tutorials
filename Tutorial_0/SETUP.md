# Setting Up an Ubuntu Virtual Machine in VirtualBox for Penetration Testing

This guide walks through installing VirtualBox, downloading Ubuntu, creating a VM, installing the OS, and configuring it with common penetration testing tools. Only use these tools against systems you own or are explicitly authorized to test.

---

## Part 1: Install VirtualBox

1. **Download VirtualBox**
   - Go to https://www.virtualbox.org/wiki/Downloads
   - Choose the installer for your host OS (Windows, macOS, or Linux).
   - Also download the **VirtualBox Extension Pack** from the same page (adds USB 2.0/3.0 support, etc.).

2. **Install VirtualBox**
   - **Windows:** Run the `.exe` installer, accept defaults, allow any driver installation prompts, then reboot if asked.
   - **macOS:** Open the `.dmg`, run the installer package. You may need to approve the kernel extension in System Settings → Privacy & Security.
   - **Linux:** Use your package manager, e.g.
     ```bash
     sudo apt update
     sudo apt install virtualbox
     ```
     or install the `.deb`/`.rpm` from the website.

3. **Install the Extension Pack**
   - Open VirtualBox → File → Tools → Extension Pack Manager → Install, and select the downloaded `.vbox-extpack` file.

---

## Part 2: Download the Ubuntu ISO

1. Go to https://ubuntu.com/download/desktop (or `/server` for Ubuntu Server).
2. Download the latest **LTS release** (recommended for stability) — e.g., Ubuntu 24.04 LTS `.iso` file.
3. (Optional but recommended) Verify the checksum:
   ```bash
   sha256sum ubuntu-24.04-desktop-amd64.iso
   ```
   Compare against the checksum listed on Ubuntu's download page.

---

## Part 3: Create the Virtual Machine

1. Open VirtualBox → click **New**.
2. **Name and Operating System:**
   - Name: `Ubuntu-PenTest` (or any name)
   - Type: Linux
   - Version: Ubuntu (64-bit)
3. **Hardware:**
   - RAM: at least 2048 MB if your host has 8GB+ (4096 MB or more recommended if your host has 16GB+)
   - CPUs: 2–4 cores
4. **Hard Disk:**
   - Create a virtual hard disk now → VDI (VirtualBox Disk Image) → Dynamically allocated
   - Size: at least 40–80 GB (pentesting tools and wordlists take space)
5. Click **Finish**.

---

## Part 4: Configure VM Settings (Before First Boot)

Select the VM → **Settings**:

- **System → Processor:** Enable PAE/NX.
- **Display → Screen:** Set Video Memory to 128 MB, enable 3D Acceleration.
- **Storage:** Click the empty optical drive → click the disk icon → **Choose a disk file** → select your Ubuntu `.iso`.
- **Network:** Adapter 1 → Attached to: **NAT** (safe default) or **Bridged Adapter** if you need the VM to appear as a separate device on your LAN (only do this on networks you're authorized to scan).
- **USB:** Enable USB 3.0 controller if you plan to use USB wireless adapters for wireless testing.

---

## Part 5: Install Ubuntu

1. Select the VM → **Start**.
2. The VM boots from the ISO. Choose **Try or Install Ubuntu**.
3. Select language → **Install Ubuntu**.
4. Keyboard layout → Continue.
5. Updates and other software:
   - Choose **Normal installation**.
   - Check **Download updates while installing**.
   - Check **Install third-party software** (drivers/codecs).
6. Installation type: **Erase disk and install Ubuntu** (this only affects the virtual disk, not your host machine).
7. Confirm the changes.
8. Select your timezone.
9. Create your user account:
   - Name, computer name, username, and a strong password.
10. Wait for installation to finish → **Restart Now**.
11. When prompted, remove the installation medium (VirtualBox usually does this automatically) → press Enter.

---

## Part 6: Post-Install Setup

1. Log in to your new Ubuntu desktop.
2. Update the system:
   ```bash
   sudo apt update && sudo apt full-upgrade -y
   ```
3. **Install Guest Additions** (improves performance, enables shared clipboard, shared folders, better display resolution):
   - VM window menu → **Devices → Insert Guest Additions CD Image**.
   - Open the mounted CD in the file manager and run:
     ```bash
     sudo apt install build-essential dkms linux-headers-$(uname -r) -y
     cd /media/$USER/VBox_GAs_*
     sudo ./VBoxLinuxAdditions.run
     ```
   - Reboot the VM.
4. **Take a snapshot** (Machine → Take Snapshot) once the base install is clean — this lets you roll back if you break something later while testing.

---

## Part 7: Set Up for Penetration Testing

There are two common approaches — pick whichever fits your goals:

### Option A: Install individual tools on plain Ubuntu

```bash
sudo apt update
sudo apt install -y nmap wireshark netcat-openbsd hydra john sqlmap \
    gobuster nikto whatweb dirb hashcat aircrack-ng tcpdump \
    metasploit-framework burpsuite
```

Notes:
- **Wireshark:** during install, choose "Yes" to allow non-root users to capture packets, then add your user:
  ```bash
  sudo usermod -aG wireshark $USER
  ```
- **Metasploit:** the Ubuntu repo version can be outdated; for the latest version use Rapid7's official installer:
  ```bash
  curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
  chmod 755 msfinstall
  sudo ./msfinstall
  ```
- **Burp Suite Community Edition:** download the `.sh` installer from https://portswigger.net/burp/communitydownload and run it, or install via `apt` if available in your repo.

#### If You're Using a Different Linux Distro (Not Kali, Not Ubuntu/Debian-based)

The `apt install` commands above only work on Debian/Ubuntu-based distros. If your VM is running a different distro, use the equivalent package manager:

**Fedora / RHEL / CentOS (`dnf`):**
```bash
sudo dnf install -y nmap wireshark netcat hydra john sqlmap \
    gobuster nikto dirb hashcat aircrack-ng tcpdump
```
- Metasploit and Burp Suite still need their official installers (see links above) — they're not in the default Fedora/RHEL repos.

**Arch Linux / Manjaro (`pacman`):**
```bash
sudo pacman -S nmap wireshark-qt netcat hydra john sqlmap \
    gobuster nikto dirb hashcat aircrack-ng tcpdump
```
- Many pentest tools (e.g. `metasploit`, `burpsuite`) are available via the **AUR** using a helper like `yay`:
  ```bash
  yay -S metasploit burpsuite
  ```

**openSUSE (`zypper`):**
```bash
sudo zypper install -y nmap wireshark netcat-openbsd hydra john sqlmap \
    gobuster nikto dirb hashcat aircrack-ng tcpdump
```

**General notes for any distro:**
- Package names occasionally differ slightly between distros (e.g. `netcat` vs `netcat-openbsd` vs `gnu-netcat`) — search your distro's package repo if a name isn't found.
- Not every tool is packaged for every distro. When a tool isn't available in your package manager, check for:
  - An official installer script (like Metasploit's `msfinstall`, shown above).
  - A Snap package: `sudo snap install <tool>` (works across most distros with snapd).
  - A Flatpak (for GUI tools like Wireshark or Burp Suite): `flatpak install flathub <tool>`.
  - Building from source via the tool's GitHub repo.
- If you'd rather not hunt for packages across distros, using **Kali or Parrot** (Option B below) avoids this entirely since the tools come pre-installed.

### Option B: Use a dedicated pentesting distro instead

If you want a full pre-built toolkit rather than assembling one on plain Ubuntu, consider running **Kali Linux** or **Parrot Security OS** as the VM instead — both are Debian-based, free, and ship with hundreds of tools pre-installed:
- Kali Linux: https://www.kali.org/get-kali/#kali-virtual-machines (official pre-built VirtualBox images are available, skipping most of the manual install)
- Parrot Security: https://www.parrotsec.org/download/

The VirtualBox setup steps (Parts 1–4) are identical; you'd just import the pre-built `.ova` image or install from their ISO instead of Ubuntu's.

### Networking for a Pentest Lab

- Keep your pentest VM's network adapter on **NAT** or a **Host-Only/Internal Network** when practicing against intentionally vulnerable targets (see below), so traffic never touches your real LAN.
- Only switch to **Bridged** networking when testing devices on a network you own or have written authorization to test.

### Practice Targets (legal, intentionally vulnerable)

Set up a second VM as a safe target to practice against:
- **Metasploitable 2/3** — deliberately vulnerable Linux VM: https://sourceforge.net/projects/metasploitable/
- **OWASP Juice Shop** — vulnerable web app (Docker container)
- **DVWA (Damn Vulnerable Web Application)**
- **TryHackMe / HackTheBox** — legal online labs with their own VPN-connected targets

Put your pentest VM and target VM(s) on the same **Internal Network** or **Host-Only Adapter** in VirtualBox so they can reach each other without touching the internet or your real network.

#### Step-by-Step: Placing Kali/Pentest VM and Target VM on the Same Isolated Network

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
   - If ping/scan succeeds, both machines are correctly isolated together on the same lab network.

7. **Double-check isolation:** from the target VM, confirm it has no route to the internet (this protects you from accidentally exposing a vulnerable machine):
   ```bash
   ping -c 2 8.8.8.8
   ```
   This should fail (timeout) if the target only has an Internal/Host-Only adapter, as intended.

---

## Troubleshooting: Drag & Drop Error (VBOX_E_DND_ERROR)

You may encounter this error when trying to drag and drop files between your host and the VM:

```
Error: Drag and drop to guest not possible -- either the guest OS does not support
this, or the Guest Additions are not installed. Result Code: VBOX_E_DND_ERROR
(0x80bb0011) Component: GuestDnDTargetWrap Interface: IGuestDnDTarget
{50ce4b51-0ff7-46b7-a138-3c6e5ac946b4} Callee: IDnDTarget
{ff5befc3-4ba3-7903-2aa4-43988ba11554}
```

This means Drag & Drop between the host and guest isn't working. Common causes:

1. Guest Additions aren't installed inside the VM.
2. Guest Additions are installed but don't match your VirtualBox version.
3. Drag & Drop is disabled in the VM settings.
4. The guest OS doesn't support VirtualBox Drag & Drop properly.

### Fix

**1. Check the Drag & Drop setting**
- Power off the VM completely.
- In VirtualBox: **VM → Settings → General → Advanced → Drag and Drop**.
- Set it to **Bidirectional** (or **Host to Guest** if you only need to copy files into the VM).

**2. Install/reinstall Guest Additions**
- Start the VM.
- From the VirtualBox window menu: **Devices → Insert Guest Additions CD Image**.
- On Ubuntu/Debian-based guests, if you hit missing build dependencies:
  ```bash
  sudo apt update
  sudo apt install build-essential dkms linux-headers-$(uname -r)
  ```
- Then run the Guest Additions installer again from the mounted CD:
  ```bash
  cd /media/$USER/VBox_GAs_*
  sudo ./VBoxLinuxAdditions.run
  ```

**3. Restart the VM**
```bash
sudo reboot
```
Then try dragging a file from the host into the VM again.

**4. Confirm version match**
Guest Additions version should match your installed VirtualBox version, e.g.:
```
VirtualBox       7.x
Guest Additions  7.x
```
A recent VirtualBox with an outdated Guest Additions ISO (or vice versa) commonly causes Drag & Drop to fail. If mismatched, download the matching Guest Additions ISO for your VirtualBox version from https://www.virtualbox.org/wiki/Downloads and re-run the install steps above.

---



- [ ] VirtualBox + Extension Pack installed
- [ ] Ubuntu LTS ISO downloaded and checksum verified
- [ ] VM created (4GB+ RAM, 40GB+ disk, 2+ CPUs)
- [ ] Ubuntu installed and updated
- [ ] Guest Additions installed
- [ ] Clean snapshot taken
- [ ] Pentesting tools installed (Option A or B)
- [ ] Network mode set appropriately (NAT/Host-Only for lab use)
- [ ] Safe, authorized practice target set up

---

**Reminder:** Only scan or attack systems you own or have explicit written permission to test. Unauthorized access to computer systems is illegal in most jurisdictions.