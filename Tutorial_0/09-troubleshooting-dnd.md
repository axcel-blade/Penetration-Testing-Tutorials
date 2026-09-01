[← Back to Index](00-index.md) | [← Previous: Networking Your Pentest Lab](08-network-lab.md)

# Troubleshooting: Drag & Drop Error (VBOX_E_DND_ERROR)

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

## Fix

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

Next: [Quick Checklist →](10-checklist.md)
