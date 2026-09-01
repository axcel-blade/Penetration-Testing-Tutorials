[← Back to Index](00-index.md) | [← Previous: Automatic (Unattended) Guest OS Install](03b-auto-configuration.md)

# Part 4: Configure VM Settings (Before First Boot)

Select the VM → **Settings**:

- **System → Processor:** Enable PAE/NX.
- **Display → Screen:** Set Video Memory to 128 MB, enable 3D Acceleration.
- **Storage:** Click the empty optical drive → click the disk icon → **Choose a disk file** → select your Ubuntu `.iso`.
- **Network:** Adapter 1 → Attached to: **NAT** (safe default) or **Bridged Adapter** if you need the VM to appear as a separate device on your LAN (only do this on networks you're authorized to scan).
- **USB:** Enable USB 3.0 controller if you plan to use USB wireless adapters for wireless testing.

---

Next: [Install Ubuntu →](05-install-ubuntu.md)
