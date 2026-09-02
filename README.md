# Vulnerable Systems Configuration

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
