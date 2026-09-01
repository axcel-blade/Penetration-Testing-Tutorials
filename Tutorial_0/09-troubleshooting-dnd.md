[← Back to Index](00-index.md) | [← Previous: Networking Your Pentest Lab](08-network-lab.md)

# Troubleshooting: Drag & Drop Error (VBOX_E_DND_ERROR)

## Basic Case: "Guest Additions not installed" error

You may first encounter this error when trying to drag and drop files between your host and the VM:

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

## Advanced Case: VERR_TIMEOUT After Everything Above Is Already Confirmed Working

Sometimes all of the basic checks pass — Guest Additions are installed and running, versions match, and Drag & Drop is set to Bidirectional — but the drop itself still fails with a timeout, e.g.:

```
DnD: Error: Moving to 612,230 (screen 0) failed (VERR_TIMEOUT)
Result Code: VBOX_E_DND_ERROR (0x80bb0011)
```

Example environment where this shows up: VM named `Ubuntu-Penetration-Testing`, VirtualBox 7.2.12 on a Windows host, Ubuntu guest.

Before going further, confirm these baseline items (all of which no longer explain the problem if already true, but are worth a final check):

- `vboxguest` kernel module loaded (`lsmod | grep vboxguest`).
- `VBoxControl --version` inside the guest matches the host VirtualBox version.
- Guest session is running **X11/Xorg**, not Wayland:
  ```bash
  echo $XDG_SESSION_TYPE
  ```
  (should print `x11`)
- `VBoxClient --draganddrop` process is running:
  ```bash
  ps aux | grep VBoxClient
  ```
- VM settings show:
  - Clipboard Mode: Bidirectional
  - Clipboard file transfers: enabled
  - Drag and Drop Mode: Bidirectional

If all of the above check out and Drag & Drop still times out, the issue is in the DnD communication channel itself, not in installation or configuration. Work through these steps in order:

### 1. Manually restart the guest DnD client and capture output

Run this in a terminal inside the guest, and **keep the terminal open** while you attempt the drag-and-drop, so you can see any error or message it produces in real time:

```bash
killall VBoxClient
VBoxClient --draganddrop
```

Then, without closing that terminal, try dragging a file from Windows into the Ubuntu window again and watch for output. Any message printed here (permission errors, protocol errors, crashes) is the most direct diagnostic clue for this class of failure.

### 2. Restart VBoxClient in the foreground with verbose logging

If the above produces no useful output, run it in the foreground with debug logging enabled to get more detail:

```bash
killall VBoxClient
VBoxClient --draganddrop -d -F
```
- `-d` enables debug output.
- `-F` keeps it in the foreground so logs print directly to the terminal instead of daemonizing.

### 3. Check host-side VBoxSVC logs

On the Windows host, VirtualBox's main service (`VBoxSVC`) logs DnD session activity. Check:
```
%USERPROFILE%\.VirtualBox\VBoxSVC.log
```
or, per-VM logs:
```
<VM folder>\Logs\VBox.log
```
Search for `DnD` or `VERR_TIMEOUT` entries around the time of the failed transfer — these often show which side the connection stalled on (host-to-guest handshake vs. guest-side drop event).

### 4. Try a smaller/simpler test file

Large files or files dragged from network-mapped or cloud-synced folders (OneDrive, etc.) on the host can trigger timeouts if Windows hasn't finished materializing the file locally. Test with a small local `.txt` file first to rule this out.

### 5. Test Drag & Drop in the opposite direction

Try Guest → Host instead of Host → Guest. If one direction works and the other doesn't, that narrows the problem to one side of the DnD protocol implementation rather than a general Guest Additions issue.

### 6. Fall back to Shared Folders or Shared Clipboard as a workaround

If DnD continues to fail after the above, it's a known class of intermittent VirtualBox DnD bugs on some host/guest/display-server combinations. As a reliable workaround while you continue investigating:
- **Shared Folders:** Devices → Shared Folders → add a Windows folder, mount it in Ubuntu, and copy files through it instead of dragging.
- **Shared Clipboard** (for small text snippets, not files): already enabled per your settings above.
- **scp/rsync over the lab's internal network**, if the VM has a reachable IP (see [Part 8: Networking Your Pentest Lab](08-network-lab.md)).

### 7. Report/track upstream if unresolved

If none of the above resolves it, this is likely a VirtualBox bug specific to your VirtualBox build/guest combination rather than a misconfiguration. Check the VirtualBox bug tracker (https://www.virtualbox.org/wiki/Bugtracker) for existing reports matching `VERR_TIMEOUT` DnD errors on your VirtualBox version, and consider filing a new report with the `VBoxClient -d -F` output and `VBoxSVC.log` excerpt attached.

---

Next: [Quick Checklist →](10-checklist.md)