[← Back to Index](00-index.md) | [← Previous: Create the Virtual Machine](03-create-vm.md)

# Part 3b: Using VirtualBox's Automatic (Unattended) Guest OS Install

Modern VirtualBox (6.1+) can automatically configure the OS during VM creation once you select an ISO in the **New Virtual Machine** wizard. This skips manually clicking through the Ubuntu installer prompts for language, user creation, etc. This screen typically appears right after you pick the ISO file, either in the same wizard or as an "Unattended Install" step.

## Where This Appears

1. Open VirtualBox → click **New**.
2. In the **ISO Image** dropdown/field, select your downloaded Ubuntu (or other) `.iso`.
3. As soon as a bootable ISO is selected, VirtualBox tries to detect the OS type/version automatically, and an **Unattended Install** section/checkbox appears (checked by default in recent versions).
4. If it's collapsed, click the **Skip Unattended Installation** checkbox to toggle it **off** (i.e., leave unattended install enabled) so the extra fields show up.

## Fields to Fill In

**Name and Operating System page:**
- **Name:** A label for the VM, e.g. `Ubuntu-PenTest`. VirtualBox uses this to auto-suggest a matching **Folder** and **ISO Image** if one exists in your downloads.
- **ISO Image:** Path to the Ubuntu `.iso` you downloaded.
- **Edition:** If the ISO contains multiple editions (e.g. Desktop/Server), pick one here.
- **Type / Version:** Usually auto-detected from the ISO (e.g. Linux / Ubuntu 64-bit). Verify it's correct; change manually if misdetected.

**Unattended Install fields (appear once an ISO is selected):**
- **Username:** The Linux user account VirtualBox will create on first boot.
- **Password / Confirm Password:** Password for that user account.
- **Hostname/Domain Name:** Sets the machine's hostname (and domain suffix, if entered) — e.g. hostname `pentestvm`, domain `local`, giving a full hostname of `pentestvm.local`.
- **Product Key:** (Windows guests only — leave blank for Ubuntu/Linux.)
- **Install in Background:** Leave checked to let installation run without taking over your screen; you can watch progress via the VM's window anytime.
- **Guest Additions:** A checkbox such as **Install Guest Additions** — enable this so VirtualBox automatically injects and installs Guest Additions during setup (saves doing it manually in [Part 6](06-post-install-setup.md)).

**Hardware page (next step in the wizard):**
- **Base Memory (RAM):** Set per [Part 3](03-create-vm.md) guidance (2048 MB+ if host has 8GB+, 4096 MB+ if host has 16GB+).
- **Processors:** 2–4 CPUs.
- **Enable EFI:** Leave off unless you specifically need UEFI boot.

**Virtual Hard Disk page:**
- **Create a Virtual Hard Disk Now:** Leave selected.
- **Disk Size:** 40–80 GB recommended for pentesting tools/wordlists.
- **Pre-allocate Full Size:** Optional — improves disk I/O performance at the cost of using the full space immediately.

## Additional Drivers / Guest Additions During Auto-Install

- If you ticked **Install Guest Additions** in the Unattended Install section, VirtualBox will mount the Guest Additions ISO automatically during the unattended setup and run the installer for you inside the guest — no need to manually do **Devices → Insert Guest Additions CD Image** afterward.
- If your host doesn't have the Guest Additions ISO cached, VirtualBox may prompt to download it — allow this if you have internet access.
- For **additional third-party drivers** (e.g. specific network or USB drivers some hardware needs), unattended install doesn't have a dedicated field for arbitrary drivers on Linux guests. Instead:
  - Let the base unattended install finish, then install any extra drivers manually after first boot via `apt`, `dkms`, or the driver vendor's instructions.
  - On Windows guests, VirtualBox's unattended installer does support an **Additional Drivers** path field for injecting `.inf` driver packages during setup — this doesn't apply to Ubuntu/Linux guests.

## Exact Field Names in the Wizard

VirtualBox labels these fields slightly differently depending on version (7.0/7.1 shown below, since that's current). Here's what to look for, screen by screen:

### Screen 1 — "Name and Operating System"

| Field label (as shown in VirtualBox) | What to enter |
|---|---|
| **Name** | VM display name, e.g. `Ubuntu-PenTest` |
| **Folder** | Where VM files are stored (auto-filled; usually leave default) |
| **ISO Image** | Path to your Ubuntu `.iso` |
| **Edition** | Only shown if the ISO has multiple editions (e.g. Desktop/Server/Live) |
| **Type** | e.g. `Linux` (auto-detected from ISO) |
| **Version** | e.g. `Ubuntu (64-bit)` (auto-detected from ISO) |
| **Skip Unattended Installation** | Checkbox — leave **unticked** to keep auto-configuration active |

### Screen 2 — "Unattended Install" (appears automatically when the box above is unticked)

| Field label (as shown in VirtualBox) | What it sets |
|---|---|
| **Username** | Linux user account created on first boot |
| **Password** | Password for that account |
| **Confirm Password** | Must match Password |
| **Hostname/Domain Name** | Single field — enter as `hostname.domain`, e.g. `pentestvm.local` → hostname becomes `pentestvm`, domain `local` |
| **Product Key** | Windows guests only — leave blank for Ubuntu |
| **Install in Background** | Checkbox — runs install without grabbing focus of the VM window |
| **Install Guest Additions** | Checkbox — auto-mounts and installs Guest Additions during setup |
| **Additional Options → Install GUI** | Some versions include this for server ISOs, to also install a desktop environment |

### Screen 3 — "Hardware"

| Field label | What it sets |
|---|---|
| **Base Memory** | RAM in MB (slider + numeric field) |
| **Processors** | Number of vCPUs |
| **Enable EFI** | Toggle for UEFI boot (leave off for standard BIOS boot) |

### Screen 4 — "Virtual Hard Disk"

| Field label | What it sets |
|---|---|
| **Create a Virtual Hard Disk Now** | Radio button — leave selected |
| **Disk Size** | Size in GB/MB (slider + numeric field) |
| **Pre-allocate Full Size** | Checkbox — fixed vs dynamically allocated disk |
| **File location** | Path/filename for the `.vdi` file |

### Screen 5 — "Summary"

Shows everything you entered above for a final review before clicking **Finish**.

---

## Example Values to Enter

Here's a filled-in example you can use as a template for a pentest lab VM:

| Field | Example value |
|---|---|
| **Name** | `Ubuntu-PenTest` |
| **Folder** | *(leave default)* |
| **ISO Image** | `C:\Users\you\Downloads\ubuntu-24.04-desktop-amd64.iso` (or your actual path) |
| **Type** | `Linux` |
| **Version** | `Ubuntu (64-bit)` |
| **Username** | `pentester` |
| **Password** | `P3ntest!2026` *(use your own strong password — this is just an example)* |
| **Confirm Password** | `P3ntest!2026` |
| **Hostname/Domain Name** | `pentestvm.local` |
| **Product Key** | *(leave blank — Linux guest)* |
| **Install in Background** | ✅ checked |
| **Install Guest Additions** | ✅ checked |
| **Base Memory** | `2048` MB (or `4096` MB if host has 16GB+) |
| **Processors** | `2` |
| **Disk Size** | `60` GB |
| **Pre-allocate Full Size** | unchecked (dynamically allocated) |

**Notes on the example:**
- `pentester` as the username avoids confusion with your host account and is easy to recognize in shell prompts (`pentester@pentestvm:~$`).
- The hostname `pentestvm.local` makes the machine easy to identify on your isolated lab network (see [Part 8: Networking Your Pentest Lab](08-network-lab.md)).
- Never reuse a real personal password here — this account only exists inside the VM, so pick something unique to the lab.

---




1. Click **Next** through Hardware and Disk pages (adjust values per [Part 3](03-create-vm.md) and [Part 4](04-configure-vm-settings.md)).
2. Click **Finish**.
3. VirtualBox boots the VM and runs the unattended install automatically — no need to click through the Ubuntu installer manually. Ubuntu will install with the username, password, and hostname you specified.
4. Once it reaches the desktop/login screen, continue with [Post-Install Setup](06-post-install-setup.md) (you can skip the Guest Additions step there if you enabled it during unattended install).

**Note:** If you'd rather control every install screen yourself (language, partitioning, third-party software prompts, etc.), leave **Skip Unattended Installation** checked and follow the manual steps in [Part 5: Install Ubuntu](05-install-ubuntu.md) instead.

---

Next: [Configure VM Settings →](04-configure-vm-settings.md)
