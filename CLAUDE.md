# nix-actions

Composite GitHub Actions for Nix flake repos, published to the GitHub
Marketplace as **OSSystems Nix Actions**
(<https://github.com/marketplace/actions/ossystems-nix-actions>).

- Root `action.yml` — the published Marketplace action (`nix flake check` +
  `nix build`). It carries the `name`, `description` (< 125 chars) and
  `branding` that the Marketplace requires.
- `update-flake/action.yml` — sub-action, used as
  `OSSystems/nix-actions/update-flake@v1`. Not separately listed (one
  Marketplace listing per repo).
- `scripts/` — shell helpers the root action runs through
  `$GITHUB_ACTION_PATH`.
- `tests/` — runnable tests for those helpers. `tests/*.test.sh` runs on a bare
  runner (no Nix), so it still reports when the Nix install itself is broken.
  Run one directly: `tests/prefetch-nix-archive.test.sh`.

## Guides

- [Releasing](docs/releasing.md) — the `vX.Y.Z` (immutable) and `vX` (movable)
  tag model and the steps to cut a release. Read before tagging or moving a tag.
- [Marketplace constraints](docs/marketplace.md) — rules the published
  `action.yml` must satisfy. Read before editing it.
