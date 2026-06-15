# Releasing

## Versioning

Two kinds of tags, both on the same release commit:

- `vX.Y.Z` (e.g. `v1.0.0`) — **immutable**. Matches a published Marketplace
  release; never move it once published.
- `vX` (e.g. `v1`) — **movable major tag**. Most callers pin `@v1`, so it must
  be fast-forwarded to each new release on the same major line. `v1` is a *tag*,
  not a branch.

## Cutting a new release

1. Land all changes on `main`.
2. Tag the immutable version and push it:
   ```
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   ```
3. Move the major tag to the same commit:
   ```
   git tag -f vX HEAD && git push -f origin vX
   ```
4. Create the GitHub release from the `vX.Y.Z` tag
   (`gh release create vX.Y.Z --title vX.Y.Z --notes ...`). On the **first**
   release of a major line, also check "Publish this Action to the GitHub
   Marketplace" in the release UI (the Marketplace checkbox is UI-only) and
   accept the Developer Agreement.

For a docs/non-release change that should reach `@v1` callers without a new
version, just move the major tag: `git tag -f v1 HEAD && git push -f origin v1`.
