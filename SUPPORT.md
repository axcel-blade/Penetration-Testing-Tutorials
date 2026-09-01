# Support

## Before opening an issue

Several tutorials already document fixes for common problems:

- **VirtualBox / VM setup issues** — check
  [Tutorial_0's troubleshooting guide](Tutorial_0/09-troubleshooting-dnd.md)
  and the [quick checklist](Tutorial_0/10-checklist.md).
- **GreenGrid lab (Tutorial_1) issues** — re-read the relevant step in
  [greengrid_walkthrough.md](Tutorial_1/greengrid_walkthrough.md); most
  target-side problems are fixed by re-running `setup_greengrid.sh` on a
  fresh VM snapshot rather than patching a partially-configured one.

## Getting help

If that doesn't resolve it, open a GitHub issue with:

- Which tutorial and step number you're on
- Your host OS and VirtualBox version
- The exact error message or unexpected behavior
- What you've already tried

## Reporting a real (non-lab) security concern

These tutorials intentionally build vulnerable machines for isolated lab
use. If you believe a tutorial or script could unintentionally affect
systems *outside* that isolated environment, please open an issue
describing the scenario rather than a pull request — see
[CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Scope

This project is maintained on a best-effort basis. It is not a substitute
for a formal penetration-testing course, and no support is provided for
using this material against systems you do not own or are not explicitly
authorized to test.
