# New Tutorial Prompt Template

A reusable prompt for generating the next `Tutorial_N` in this repo. Paste
it as-is (or into a fresh session) whenever you want to add another lab —
it's parameterized so it works the same way every time, not just once.

```
Create the next Tutorial_N in this repo, following the exact pattern
established by Tutorial_1 (GreenGrid) — read Tutorial_1/GreenGrid_Tutorial.md
and Tutorial_1/setup_greengrid.sh first for the structure, tone, and safety
conventions to match.

Step 1 — Pick N: look at the existing Tutorial_* directories and use the
next integer.

Step 2 — Pick the target OS at random (Windows or Linux) using an actual
random source (e.g. shell $RANDOM, not your own judgment/bias). State which
one was picked before continuing.

Step 3 — Pick a vulnerability chain not yet used by an existing tutorial in
this repo (check prior Tutorial_N walkthroughs' "Summary of the
Vulnerability Chain" sections to avoid repeats). Choose 2-3 chained issues
from a pool appropriate to the OS, for example:

  Linux pool: exposed .git repo, weak sudo NOPASSWD + GTFOBins pivot, SUID
  misconfiguration, cron job privilege escalation, weak/reused SSH
  credentials, exposed backup/config file, world-writable service unit,
  Docker socket exposure, path-hijackable script called by a privileged
  cron/service.

  Windows pool: unquoted service path, weak service ACL allowing binary
  replacement, AlwaysInstallElevated MSI policy, scheduled task running as
  SYSTEM with a world-writable script/binary, exposed backup/config file
  with plaintext credentials, weak SMB share permissions, insecure registry
  ACL on a privileged auto-run key, weak local admin credentials reused
  from a leaked file.

Step 4 — Invent a new fictional company/theme (not GreenGrid or any
previously used theme) that plausibly motivates why each vulnerability
exists.

Deliverables:

1. Tutorial_N/setup_<theme>.<sh|ps1> — a provisioning script (bash for
   Linux, PowerShell for Windows) for a fresh, throwaway VM that builds in
   the chosen vulnerability chain. Must include:
   - A header comment block warning it installs real vulnerabilities, must
     only run on a throwaway/isolated VM with no internet-facing NIC, and
     will be destroyed afterward — match the tone of setup_greengrid.sh's
     warning block.
   - A short delay/confirmation step before making changes (the
     `sleep 10` + "Press Ctrl+C to abort" pattern, or the PowerShell
     equivalent).
   - Section-header comments throughout, same style as setup_greengrid.sh.
   - Three flags dropped at increasing access levels: EASY_FLAG.txt
     (findable via enumeration alone, no exploitation), INTERMEDIATE_FLAG.txt
     (after a low-privilege foothold), HARD_FLAG.txt (after privilege
     escalation to root/SYSTEM/Administrator).

2. Tutorial_N/<theme>_Tutorial.md — a walkthrough with the same section
   structure as GreenGrid_Tutorial.md:
   - Title, Theme, Scope/Legal notice, Flags list
   - Part 0 – Build (provisioning steps, snapshot reminder)
   - Part 1 – Enumeration
   - Part 2 – Identify Vulnerabilities
   - Part 3 – Gain Access
   - Part 4 – Privilege Escalation
   - Part 5 – Capture the Flags
   - Summary of the Vulnerability Chain + root-cause lessons for defenders
   - Cleanup section
   - After every command block that has flags/switches, add a bullet list
     explaining each one — this is a standing repo convention (see the
     "Explain command-line flags" commit on Tutorial_1 for the expected
     format/depth).

Follow CONTRIBUTING.md: branch off develop as
feature/tutorial-N-<theme-slug>, add Tutorial_N to README.md's tutorial
table, and don't commit directly to main.
```
