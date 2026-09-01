[← Back to Index](00-index.md) | [← Previous: Install Ubuntu](05-install-ubuntu.md)

# Part 6: Post-Install Setup

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

Next: [Set Up for Penetration Testing →](07-pentest-setup.md)
