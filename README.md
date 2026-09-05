# Penetration Testing Tutorials

A collection of self-contained tutorials for building intentionally
vulnerable lab VMs, for **authorized security training and CTF-style
practice** (pentest coursework, home-lab study).

## ⚠️ Legal / Scope Notice

Everything in this repo builds machines with real, working
vulnerabilities. Only use these tutorials against systems you own or are
explicitly authorized to test, and only on an isolated / NAT'd lab network
with no internet-facing NIC. Unauthorized access to computer systems is
illegal in most jurisdictions. See each tutorial's own notice for
lab-specific scope details.

## Tutorials

| Lab | What it covers |
|---|---|
| [Tutorial_0](Tutorial_0/00-index.md) | Building the base attacker/lab environment: installing VirtualBox, creating an Ubuntu VM, and configuring it with common penetration-testing tools |
| [Tutorial_1](Tutorial_1/greengrid_walkthrough.md) | GreenGrid Sensor Portal — a vulnerable web app target (`setup_greengrid.sh`) with a three-tier, flag-based walkthrough: enumeration, an exposed `.git` repo leaking credentials, and sudo privilege escalation |
| [Tutorial_2](Tutorial_2/BrightSmile_Walkthrough.md) | BrightSmile Dental Clinic — a vulnerable target (`setup_brightsmile.sh`) with a three-tier, flag-based walkthrough: anonymous FTP enumeration, leaked DB/SSH credentials for lateral movement, and a SUID PATH-hijack privilege escalation |
| [Tutorial_3](Tutorial_3/Elmridge_Walkthrough.md) | Elmridge Community Library — a vulnerable target (`setup_elmridge.sh`) with a three-tier, flag-based walkthrough: unrestricted file-upload RCE, a base32-encoded credential leaked via a world-readable cron job, and a group-writable root cron script privilege escalation |
| [Tutorial_4](Tutorial_4/Nimbus_Home_Walkthrough.md) | Nimbus Home — a vulnerable smart-home-hub target (`setup_nimbushome.sh`) with a three-tier, flag-based walkthrough: an exposed migration backup in the web root, a base64-encoded credential leaked via a world-readable systemd unit, and a misassigned `cap_setuid` capability privilege escalation |
| [Tutorial_5](Tutorial_5/Forge_CI_Walkthrough.md) | Forge CI — a vulnerable self-hosted CI target (`setup_forgeci.sh`) with a three-tier, flag-based walkthrough: an unauthenticated debug panel leaking a fallback credential, a hex-encoded deploy key in a world-readable state file, and a writable systemd unit paired with a narrowly scoped sudo grant for privilege escalation |
| [Tutorial_6](Tutorial_6/MakerNest_Walkthrough.md) | MakerNest — a vulnerable tool-reservation kiosk target (`setup_makernest.sh`) with a three-tier, flag-based walkthrough: path traversal in a report-export endpoint, a crackable password hash in a leftover legacy Basic-Auth file, and a tar-wildcard injection via a group-writable archive staging directory for privilege escalation |
| [Tutorial_7](Tutorial_7/Fernwood_Radio_Walkthrough.md) | Fernwood Community Radio — a vulnerable internet-radio-station target (`setup_fernwoodradio.sh`) with a three-tier, flag-based walkthrough: an upload-filter bypass, a crackable password hash in a retired Basic-Auth file, and a Python module search-path hijack in a root cron job for privilege escalation |
| [Tutorial_10](Tutorial_10/Harborview_Hotel_Walkthrough.md) | Harborview Boutique Hotel — a vulnerable staff-portal target (`setup_harborview.sh`), worked with Metasploit, with a three-tier, flag-based walkthrough: an unrestricted-upload RCE via an `msfvenom` PHP meterpreter payload, a password-protected archive cracked off a guest Samba share, and a SUID-root Python interpreter for privilege escalation |

Each `Tutorial_N/` directory is independent — start with `Tutorial_0` if you
don't yet have a lab environment set up, or jump straight to a later
tutorial's target if you already do.

## Prerequisites

- A host machine capable of running VirtualBox with at least one guest VM
- An Ubuntu Server/Desktop ISO (see [Tutorial_0](Tutorial_0/02-download-ubuntu-iso.md))
- Basic familiarity with the Linux command line

## Contributing

New tutorials and fixes are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for the repo's structure conventions and workflow.

## Getting Help

See [SUPPORT.md](SUPPORT.md).
