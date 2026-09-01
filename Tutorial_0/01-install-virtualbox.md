[← Back to Index](00-index.md)

# Part 1: Install VirtualBox

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

Next: [Download the Ubuntu ISO →](02-download-ubuntu-iso.md)
