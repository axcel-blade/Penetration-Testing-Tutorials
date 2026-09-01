# Repository Conventions

## Commits & Git Workflow

- Never add an AI/bot as a co-author on commits (no `Co-Authored-By: Claude` or similar).
- When code is updated: `git add`, `git commit`, `git push`.
- When code changes, refactor/update the affected markdown documentation to match.
- Update the version number everywhere it appears (not just one file) when it changes.
- Use branches for changes; create new branches as needed rather than committing directly to `main`.
- Add comments in code changes made in this repo.

## Git Flow

Branch model: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`

- `main` — production-ready, released state.
- `develop` — integration branch for the next release.
- `feature/*` — individual features/changes, branched from and merged back into `develop`.
- `release/*` — release preparation, branched from `develop`, merged into `main` and `develop`.
- `hotfix/*` — urgent production fixes, branched from `main`, merged into `main` and `develop`.

## GitHub Markdown File Types

| File Type | Purpose |
|---|---|
| `README.md` | Main project description shown on repo homepage |
| `CONTRIBUTING.md` | Contribution guidelines |
| `LICENSE.md` | License information |
| `CODE_OF_CONDUCT.md` | Community rules |
| `SECURITY.md` | Security policy and vulnerability reporting |
| `SUPPORT.md` | How users can get help |
| `CHANGELOG.md` | Version history and updates |
| `TODO.md` | Task tracking |
| `ROADMAP.md` | Future plans/features |
| `docs/*.md` | Documentation pages |
| `wiki/*.md` | GitHub Wiki pages |
| `.github/ISSUE_TEMPLATE/*.md` | Issue templates |
| `.github/PULL_REQUEST_TEMPLATE.md` | Pull request template |
| `.github/DISCUSSION_TEMPLATE/*.md` | Discussion templates |
