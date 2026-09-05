# Repository Conventions

## Project Overview

This repo is a collection of self-contained tutorials for building intentionally
vulnerable lab VMs for authorized security training / CTF-style practice
(e.g. pentest coursework, home-lab study). Each `Tutorial_N/` directory is one
lab and is independent of the others.

Two patterns exist so far:
- **Guide-only** (`Tutorial_0/`): a numbered, multi-part markdown walkthrough
  (`00-index.md`, `01-...md`, `02-...md`, ...) with `00-index.md` as the
  table of contents linking the rest in order.
- **Guide + build script** (`Tutorial_1/`): a single walkthrough markdown file
  plus a `setup_*.sh` provisioning script that stands up the intentionally
  vulnerable target.

Every tutorial and script must carry an explicit legal/scope notice stating
the material is for use only against systems the reader owns or is
authorized to test, and vulnerable targets must be built for an isolated/
NAT'd lab network only (never internet-facing). Preserve this notice when
editing existing tutorials, and include one in any new tutorial or script.

## Adding or Editing a Tutorial

- New labs go in a new `Tutorial_N/` directory, `N` incrementing from the
  highest existing tutorial.
- Follow whichever existing pattern fits (numbered multi-file guide with an
  index, or single walkthrough + setup script) rather than inventing a third.
- Numbered guide files use a two-digit prefix (`01-`, `02-`, ...); update
  `00-index.md`'s contents list and cross-links whenever files are added,
  renamed, reordered, or removed.
- Setup scripts (`setup_*.sh`) should keep the existing safety pattern: a
  header comment block explaining what the script does and warning it must
  only run on a throwaway/isolated VM, and a short `sleep`-based abort window
  before making changes.
- If a lab uses capture-the-flag-style markers (e.g. `EASY_FLAG.txt`,
  `INTERMEDIATE_FLAG.txt`, `HARD_FLAG.txt`), keep that naming scheme and
  document the difficulty tiers in the walkthrough.
- Include a spoiler-style **Flag Hints** section right after the Flags
  list: one collapsible `<details><summary>Hint: EASY_FLAG</summary>...`
  block per flag (three total), each giving a nudge toward the relevant
  misconfiguration/technique without naming the exact file, command, or
  credential — so a reader can attempt each flag on their own before
  falling back to the full step-by-step walkthrough that follows.

## Target OS Selection

When asked to create a new tutorial without the target OS being specified,
**randomly pick either Windows or Linux** for that lab's target machine
rather than defaulting to Ubuntu every time — state which one was picked
(and that it was chosen at random) at the top of the walkthrough. If the
user names an OS explicitly, use that instead.

- **Linux target:** follow the existing pattern — an Ubuntu Server VM
  provisioned by a `setup_*.sh` bash script, per the conventions above.
- **Windows target:** provision with a `setup_<name>.ps1` PowerShell
  script instead of a bash script, still following the same shape: a
  warning banner, a short abort window before making changes, low-priv
  user accounts (`net user` / `New-LocalUser`) with a weak/guessable
  password, one realistic initial-access vulnerability, the same
  `EASY_FLAG.txt` / `INTERMEDIATE_FLAG.txt` / `HARD_FLAG.txt` three-tier
  structure, and Windows Firewall rules (`New-NetFirewallRule`) scoped to
  only the intended ports. Adapt tooling/reasoning in the walkthrough to
  the Windows equivalents (e.g. `nmap`/`crackmapexec`/`enum4linux-ng` for
  SMB/RDP/WinRM enumeration, `evil-winrm`/`psexec.py` for access,
  Windows privesc reasoning — unquoted service paths, weak service/
  registry ACLs, AlwaysInstallElevated, token/privilege abuse, scheduled
  tasks — in place of GTFOBins/sudo/SUID reasoning) while keeping every
  other structural convention in this file (flag tiers, legal/scope
  notice, isolated-network-only requirement, README table update)
  identical to the Linux labs.
- Keep picking randomly between the two on each new tutorial (don't let
  the set drift to all-Linux or all-Windows) unless the user specifies
  otherwise.

## Tool Variety

Each new tutorial should give the reader a **new-tool experience**, not
just a re-run of the same handful of commands. Before writing a
walkthrough, check which tools the existing `Tutorial_N` walkthroughs
already lean on (`nmap`, `gobuster`, `hydra`, `John`/`Hashcat`, etc. show
up repeatedly since they're always-appropriate defaults) and deliberately
work in at least one or two tools from Kali's broader toolset that
haven't been the star of a prior tutorial, where they genuinely fit the
vulnerability chain — e.g. `smbclient`/`enum4linux-ng`/`crackmapexec` for
SMB, `ffuf`/`feroxbuster`/`wfuzz` as gobuster alternatives, `whatweb`/
`nikto`/`wpscan` for web fingerprinting, `sqlmap` for SQLi, `zip2john`/
`fcrackzip`/`pdfcrack`/`bkcrack` for format-specific cracking, `msfconsole`/
`msfvenom` for a Metasploit-driven walkthrough, `evil-winrm`/`psexec.py`/
`crackmapexec` for Windows targets, `responder`/`impacket` scripts for
Windows credential relay/abuse, `searchsploit`, `wireshark`/`tcpdump` for
traffic analysis, etc. Don't force a tool in where it doesn't fit the
planted vulnerability — pick whichever ones are the natural way to
exploit what the setup script actually planted, but treat "have I used
this tool in an earlier tutorial already" as one factor when there's a
genuine choice between equally-valid tools for a step.

## Penetration Technique Variety

Beyond varying tools and encodings, vary the actual **attack techniques**
(the initial-access vector, the lateral-movement mechanism, and the
privilege-escalation primitive) so the rotating set gives readers a new
class of real-world attack to practice each time, not just a new theme
wrapped around a familiar bug. Before designing a new tutorial's chain,
check what's already been used and deliberately pick something new for
at least the initial-access step:

- **Initial access already used:** exposed `.git` repo (T1), anonymous
  FTP (T2), unrestricted/blacklist-bypassable file upload (T3, T7, T10),
  exposed config/migration backup in the web root (T4), unauthenticated
  debug panel (T5), path traversal (T6), SQL injection (T8), OS command
  injection (T9).
- **Lateral movement / intermediate misconfiguration already used:**
  `.git` history leak (T1), DB-stored leaked credential (T2), leaked
  credential via world-readable cron/systemd/state files (T3, T4, T5),
  legacy Basic-Auth credential files (T6, T7), an encrypted backup with
  the key alongside it (T8), an unauthenticated internal service (T9),
  a guest-accessible file share (T10).
- **Privilege escalation already used:** sudo NOPASSWD + GTFOBins pivot
  (T1), custom SUID binary + `$PATH` hijack (T2), group-writable root
  cron script (T3), misassigned Linux capability (T4), writable systemd
  unit + narrow sudo (T5), tar-wildcard injection (T6), Python
  module-search-path hijack (T7), sudoers `LD_PRELOAD` leak (T8),
  `docker`-group socket abuse (T9), a stray SUID bit on a stock
  interpreter (T10).

Untapped techniques worth reaching for on future tutorials (pick
whichever genuinely fits the theme's fiction — don't force one in):
- **Initial access:** SSRF reaching an internal-only admin API, XXE in
  an XML-accepting endpoint, insecure deserialization (PHP object
  injection, a Python `pickle` loader), Server-Side Template Injection
  (SSTI), an outdated/vulnerable CMS plugin with a known CVE, LFI
  chained with Apache access-log poisoning, WebDAV with `PUT` enabled,
  an unauthenticated NoSQL/search datastore (MongoDB, Elasticsearch)
  exposing data directly.
- **Lateral movement:** an unauthenticated key-value/secrets store
  (etcd, Consul, HashiCorp Vault misconfig), SNMP with a default/public
  community string, a leaked SSH private key via agent forwarding or a
  world-readable `known_hosts`, a Docker registry pull revealing secrets
  baked into an image layer, an exposed message queue (RabbitMQ/AMQP)
  with default credentials.
- **Privilege escalation:** NFS export with `no_root_squash`, a
  world-writable `/etc/ld.so.preload` (system-wide, distinct from the
  sudoers `LD_PRELOAD` leak already used), `disk`/`lxd`/`adm` group
  abuse (siblings of the `docker`-group technique but mechanically
  different), a writable PAM configuration, an `at`/`batch` job abuse,
  or reasoning through a known local-exploit CVE via `searchsploit`
  against a deliberately outdated package (without literally
  reproducing a dangerous unpatched kernel exploit on the lab image).

Keep a running mental (or literal, via the README table and setup
scripts) tally so the set doesn't quietly converge on "just SQLi and
sudo misconfig" — the goal is breadth of real-world attacker experience
across the whole rotating set, not just breadth of tools.

## Decoding Techniques

Where a lab's chain calls for a leaked or obscured credential (most
labs' intermediate tier fits this), route it through a genuine decoding
or offline-cracking step rather than handing it over in plaintext, and
vary *which* technique is used from one tutorial to the next rather than
repeating the same encoding every time. Already used in this set —
check before picking one for a new tutorial:
- Base32 (Tutorial_3)
- Base64 (Tutorial_2's DB-stored blob, Tutorial_4's systemd-unit leak)
- Hex (Tutorial_5's cached deploy key)
- SHA-512 crypt hash cracking with John/Hashcat (Tutorial_6, Tutorial_7)
- OpenSSL AES symmetric decryption with a leaked passphrase (Tutorial_8)
- Zip-password cracking with `zip2john`/`fcrackzip` (Tutorial_10)

Still untapped, good candidates for the next tutorial: ROT13/ROT47,
URL-encoding (possibly double/nested), Base85/ASCII85, a recoverable
single-byte or repeating-key XOR, UUencoding, NTLM/MD5/bcrypt hash
cracking, or a `steghide`/binwalk-style data-hiding technique. Pick the
one that fits the theme's fiction (e.g. a legacy tool that only speaks
UUencoding, a "quick obfuscation" someone bolted onto a config file) —
never force a decoding step where the natural leak would just be
plaintext.

## Commits & Git Workflow

- Never add an AI/bot as a co-author on commits (no `Co-Authored-By: Claude` or similar).
- When code is updated: `git add`, `git commit`, `git push`.
- When a script or lab environment changes, update the corresponding
  walkthrough markdown (and `00-index.md` links, if applicable) to match.
- Use branches for changes; create new branches as needed rather than committing directly to `main`.
- Add comments in code changes made in this repo (shell scripts especially —
  follow the section-header comment style already used in `setup_greengrid.sh`).

## Git Flow

Branch model: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`

- `main` — production-ready, released state.
- `develop` — integration branch for the next release.
- `feature/*` — individual features/changes, branched from and merged back into `develop`.
- `release/*` — release preparation, branched from `develop`, merged into `main` and `develop`.
- `hotfix/*` — urgent production fixes, branched from `main`, merged into `main` and `develop`.
