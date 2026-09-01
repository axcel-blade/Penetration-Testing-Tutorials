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
