## Summary

<!-- What does this PR add or change? -->

## Type of change

- [ ] New tutorial (`Tutorial_N/`)
- [ ] Fix/update to an existing tutorial
- [ ] Repo/process change (docs, templates, CI, etc.)

## Branch

- [ ] Branched from `develop` (not `main`)
- [ ] Branch name follows `feature/*`, `release/*`, or `hotfix/*` per [CONTRIBUTING.md](../CONTRIBUTING.md#commits--branching)
- [ ] Target branch for this PR is `develop` (or `main`, for a `release/*`/`hotfix/*` PR)

## Checklist (new or changed tutorial content)

- [ ] Tutorial/script carries an explicit legal/scope notice (isolated lab use only)
- [ ] Vulnerable targets are scoped to an isolated/NAT'd network, never internet-facing
- [ ] Follows an existing pattern — guide-only with `00-index.md`, or guide + `setup_*.sh` — rather than a new one
- [ ] `00-index.md` contents/links updated if files were added, renamed, reordered, or removed
- [ ] No live credentials, keys, or data from real (non-lab) systems included
- [ ] Shell script changes are commented, section-header style

## Testing

<!-- How did you verify this? e.g. ran setup_*.sh on a fresh VM, walked through the tutorial end to end -->
