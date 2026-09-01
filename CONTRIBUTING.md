# Contributing

Thanks for considering a contribution to this repo. It collects tutorials
for building intentionally vulnerable lab VMs for authorized security
training, so contributions are held to a higher bar around safety and
legal framing than a typical project.

## Ground rules

- Every tutorial and script must carry an explicit legal/scope notice
  stating the material is for use only against systems the reader owns or
  is authorized to test.
- Vulnerable targets must be built for an isolated/NAT'd lab network only
  — never internet-facing. Setup scripts should warn about this loudly
  before making changes (see `Tutorial_1/setup_greengrid.sh` for the
  existing pattern: header comment block + short `sleep`-based abort
  window).
- Don't submit tooling aimed at real, non-lab targets, and don't include
  live credentials, keys, or data from systems you don't own.

## Adding or editing a tutorial

Adding a whole new lab? [NEW_TUTORIAL_PROMPT.md](NEW_TUTORIAL_PROMPT.md) is
a reusable, parameterized prompt that generates the next `Tutorial_N` in
this exact style (OS picked at random, vulnerability chain checked against
prior tutorials so it doesn't repeat) — use it instead of writing one from
scratch.

- New labs go in a new `Tutorial_N/` directory, `N` incrementing from the
  highest existing tutorial.
- Follow one of the existing patterns rather than inventing a third:
  - **Guide-only** (see `Tutorial_0/`): a numbered, multi-part markdown
    walkthrough (`00-index.md`, `01-...md`, `02-...md`, ...) with
    `00-index.md` as the table of contents.
  - **Guide + build script** (see `Tutorial_1/`): a single walkthrough
    markdown file plus a `setup_*.sh` provisioning script.
- Numbered guide files use a two-digit prefix (`01-`, `02-`, ...); update
  `00-index.md`'s contents list and cross-links whenever files are added,
  renamed, reordered, or removed.
- If a lab uses capture-the-flag-style markers (e.g. `EASY_FLAG.txt`,
  `INTERMEDIATE_FLAG.txt`, `HARD_FLAG.txt`), keep that naming scheme and
  document the difficulty tiers in the walkthrough.
- When a script or lab environment changes, update the corresponding
  walkthrough markdown (and `00-index.md` links, if applicable) to match.

## Commits & branching

Branch model: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`.

- `main` — production-ready, released state.
- `develop` — integration branch for the next release.
- `feature/*` — individual features/changes, branched from and merged
  back into `develop`.
- `release/*` — release preparation, branched from `develop`, merged into
  `main` and `develop`.
- `hotfix/*` — urgent production fixes, branched from `main`, merged into
  `main` and `develop`.

Branch off `develop` for your change (e.g. `feature/tutorial-2-...`) rather
than committing directly to `main`, and open a pull request into `develop`.

- Comment shell scripts, especially section headers — follow the style
  already used in `setup_greengrid.sh`.
- Do not add an AI/bot as a commit co-author.

## Reporting a vulnerability in this tooling itself

If you find a way one of these labs could unintentionally affect a system
outside its intended isolated network (as opposed to the deliberate,
documented vulnerabilities the lab exists to teach), please open an issue
describing it rather than a pull request.
