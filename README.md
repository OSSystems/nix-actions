# nix-actions

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-OSSystems%20Nix%20Actions-blue?logo=github)](https://github.com/marketplace/actions/ossystems-nix-actions)

Composite GitHub Actions for Nix flake repos. Replaces copy-pasted CI and
flake-update boilerplate with two actions you drop into a job step.

- `action.yml` (root) - `nix flake check` + optional `nix build` of explicit
  attributes (with optional GitHub App token + Nix install/cache).
- `update-flake/action.yml` - scheduled `flake.lock` bump + PR.

They run as a **step inside your job**: you pick the runner and can add your own
steps - artifact upload, deploy - before or after, on the same runner and Nix
store.

## Quick start

```yaml
name: CI
on:
  push: { branches: [main], tags: ["*"] }
  pull_request: { types: [opened, ready_for_review, synchronize] }

jobs:
  ci:
    runs-on: self-hosted
    steps:
      - uses: ossystems/nix-actions@v1
```

The action checks out the repo by default, so the snippet above already runs
`nix flake check` and, with no extra inputs, builds every `nixosConfigurations`
host and every `devShells` entry the flake exposes (`build-hosts` and
`build-devshells` default on; a flake with neither builds nothing). Set them to
`"false"` to opt out.

On a GitHub-hosted runner (no Nix preinstalled), set `install-nix: true` to
install Nix and restore the store cache:

```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: ossystems/nix-actions@v1
        with:
          install-nix: true   # public flake, no token needed
```

See [`examples/`](./examples) for self-hosted, ubuntu, explicit-build, artifact
and update-flake callers.

## `nix-actions` (CI) inputs

| Input | Default | Description |
|-------|---------|-------------|
| `token-owner` | `""` | Org to scope a GitHub App token to (private flake inputs). Empty disables the token. |
| `client-id` | `""` | GitHub App Client ID. Preferred over `app-id`. Required when `token-owner` is set. |
| `app-id` | `""` | **Deprecated** — use `client-id`. GitHub App ID, used only when `token-owner` is set and `client-id` is empty. |
| `app-private-key` | `""` | GitHub App private key. Required when `token-owner` is set. |
| `install-nix` | `"false"` | `"true"` to install Nix + restore cache (hosted runners). `"false"` on self-hosted with Nix. |
| `checkout` | `"true"` | `"true"` to checkout first. Set `"false"` if the job already checked out. |
| `fetch-depth` | `"1"` | Checkout fetch-depth. |
| `ref` | `""` | Git ref to checkout (when `checkout` is true). Empty uses the ref that triggered the run. |
| `flake-check` | `"true"` | `"true"` to run `nix flake check`. |
| `flake-check-args` | `""` | Extra args for `nix flake check`. |
| `trust-flake` | `"true"` | `"true"` to honor the flake's own `nixConfig` (`extra-substituters`, `extra-trusted-public-keys`) on every nix command via `NIX_CONFIG`, so its binary caches are used. `"false"` to ignore it. |
| `build-attrs` | `""` | Installables to `nix build` (e.g. `.#foo .#bar`). On this explicit path you may interleave `nix build` flags (e.g. `.#foo -o result`); they are passed through and the bare tokens stay the build labels. The value `matrix` builds every attr from `.#githubActions.<matrix-name>` in one job. Empty skips the build. |
| `build-args` | `-L --keep-going` | Args passed to `nix build` before the attrs. Applies to every build path (`matrix`, `build-hosts`, `build-devshells`, explicit). |
| `matrix-name` | `matrix` | When `build-attrs` is `matrix`, which `.#githubActions.<name>` to read the list from. |
| `build-hosts` | `"true"` | Build `config.system.build.toplevel` of every `.#nixosConfigurations` entry in one job (default on). Labelled by host name. `"false"` to skip. Combines with `build-attrs`. Flakes with no hosts build nothing. |
| `build-devshells` | `"true"` | Build every `.#devShells.<system>.<name>` in one job (default on), for the systems this runner can build (`system` plus `extra-platforms`). Labelled `devshell-<name>-<system>`. `"false"` to skip. Combines with `build-attrs` and `build-hosts`. Flakes with no dev shells build nothing. |
| `emulate-systems` | `""` | Space-separated extra Linux platforms to build under QEMU (e.g. `aarch64-linux`). Registers binfmt and adds them to `extra-platforms`. Empty disables emulation. |
| `checks` | `"false"` | `"true"` to report each built attribute as its own check run (one status per build in the PR Checks tab), instead of one combined build. Needs `checks:write`. Serializes the builds. |
| `run` | `""` | Command to run inside a dev shell (`nix develop --command`). Empty skips it. |
| `devshell` | `""` | Installable for the dev shell (e.g. `.#ci`), used by `run` and `export-devshell`. Empty uses the flake's default dev shell. |
| `export-devshell` | `"false"` | `"true"` to load `devshell` into the job environment so every later step runs inside it (setup only; skips the built-in flake-check, build and run). See below. |
| `ssh-private-key` | `""` | SSH private key for tools that clone private repos over SSH (e.g. `west update`). Installed at `~/.ssh/id_rsa`. Empty installs no key. |
| `ssh-known-hosts` | `github.com` | Space-separated hosts added to `known_hosts` via `ssh-keyscan` when `ssh-private-key` is set. |

Output `token`: the minted App token (empty when `token-owner` is unset), so
later steps can reuse it.

## `update-flake` inputs

The job must set `permissions: { contents: write, pull-requests: write }`.

| Input | Default | Description |
|-------|---------|-------------|
| `base-branch` | `main` | Branch to update against. |
| `token-owner` | `""` | Org for the App token. Empty falls back to `GITHUB_TOKEN`. |
| `client-id` | `""` | GitHub App Client ID. Preferred over `app-id`. Required when `token-owner` is set. |
| `app-id` | `""` | **Deprecated** — use `client-id`. GitHub App ID, used only when `token-owner` is set and `client-id` is empty. |
| `app-private-key` | `""` | GitHub App private key. Required when `token-owner` is set. |
| `install-nix` | `"false"` | `"true"` to install Nix (hosted runners). |
| `checkout` | `"true"` | `"true"` to checkout first. Set `"false"` if the job already checked out. |
| `reviewers` | `""` | Comma-separated PR reviewers. |
| `pr-labels` | `dependencies\nautomated` | Newline-separated PR labels. |
| `auto-merge` | `"true"` | Enable PR auto-merge. |
| `merge-method` | `rebase` | `rebase` \| `merge` \| `squash`. |

## Secrets

Pass secrets explicitly as inputs (`client-id: ${{ secrets.RUNNER_CLIENT_ID }}`).
Only needed when `token-owner` is set.

## Matrix builds

If your flake exposes a `githubActions` matrix (via `nix-github-actions`), set
`build-attrs: matrix` and the action builds every declared attribute in the same
job, with Nix scheduling them in parallel:

```yaml
- uses: ossystems/nix-actions@v1
  with:
    build-attrs: matrix
    # matrix-name: build-systems-matrix   # default "matrix"
```

This is one job and one check. It does not fan out across runners or produce a
check per attribute - for that, keep the matrix in your own workflow with a
`strategy.matrix` over the same `nix eval` output and call this action per cell.

### NixOS hosts

For a repo whose flake exposes `nixosConfigurations`, the action builds the
`config.system.build.toplevel` of every host in one job by default, with no
`githubActions` matrix output to maintain. Set `build-hosts: false` to skip:

```yaml
- uses: ossystems/nix-actions@v1
  with:
    build-hosts: false   # default is true
```

Each build is labelled by the host name (useful with `checks: true`). All hosts
build on one runner, so hosts targeting a non-native system need `emulate-systems`
or a remote builder. Use `matrix` instead when the flake already exposes a
`githubActions` matrix you want to reuse.

### Dev shells

To warm the dev environment cache, the action builds every
`.#devShells.<system>.<name>` in one job by default, with no `githubActions`
matrix output to maintain. Set `build-devshells: false` to skip:

```yaml
- uses: ossystems/nix-actions@v1
  with:
    build-devshells: false   # default is true
```

Only the systems this runner can build are attempted: its `system` plus whatever
`extra-platforms` is configured, which `emulate-systems` feeds. A self-hosted
runner uses its own `nix.conf`. Each build is labelled `devshell-<name>-<system>`
(useful with `checks: true`). Systems reachable only through a remote builder are
not auto-detected; list them in `extra-platforms` or keep a `matrix`.

### Emulated cross-arch

To build a multi-arch Linux matrix on a single runner with no ARM runner or
remote builder, set `emulate-systems`. The action registers QEMU binfmt and adds
the systems to `extra-platforms`, so `aarch64-linux` derivations build under
emulation:

```yaml
- uses: ossystems/nix-actions@v1
  with:
    install-nix: true
    emulate-systems: aarch64-linux
    build-attrs: matrix
```

### Status per build

By default the matrix builds in one combined `nix build`, so the run shows a
single status. Set `checks: true` to instead report each built attribute as its
own check run, so every build (package, system, image, whatever your matrix
declares) gets an individual entry in the PR Checks tab:

```yaml
jobs:
  ci:
    permissions:
      contents: read
      checks: write
    steps:
      - uses: ossystems/nix-actions@v1
        with:
          build-attrs: matrix
          checks: true
```

The check run is created with the job token (the App token when `token-owner` is
set, else `GITHUB_TOKEN`), which needs `checks: write`. With `GITHUB_TOKEN`,
declare it in the job's `permissions`. That block is an allowlist: list
`contents: read` too, or the checkout loses repo access. With an App token,
grant the App the `Checks` write permission instead.

The check is labelled by the matrix entry's own name, and its output carries the
tail of that build's log (last ~60k), so each derivation's log is readable from
its own check in the PR Checks tab without opening the job. This needs the token
to have `checks:write`, and it serializes the builds (no cross-attr Nix
parallelism). The job itself still fails if any build fails, so job-level branch
protection keeps working. Empty or `false` keeps the single combined build.

## Run in a dev shell

Set `run` to execute a command inside the flake's dev shell (`nix develop
--command`), so checks/linters/tests run with the exact tooling the shell
pins, with no extra step to enter the environment:

```yaml
- uses: ossystems/nix-actions@v1
  with:
    flake-check: false
    run: pytest -q
```

`devshell` picks a non-default shell (e.g. `devshell: .#ci`). It combines with
the build inputs: the build runs first, then the command. To run only the
command, set `flake-check: false` and leave the build inputs empty.

## Load a dev shell into the whole job (`export-devshell`)

`run` runs a single command in the shell. When a job has many steps that all
need the shell - third-party actions (test-result publishers, artifact upload),
conditional `if: failure()` steps, steps that write to `$GITHUB_ENV` - set
`export-devshell: true`. The action loads the dev shell into the job environment
once, so every later step in the job runs inside that shell (env-export via
`nicknovitski/nix-develop`), with the Nix install, GitHub App token and SSH key
setup it already does. In this mode the action does setup only and skips its own
`flake-check`, build and `run`, so you add your own steps after it:

```yaml
jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: ossystems/nix-actions@v1
        with:
          devshell: .#ci
          export-devshell: true
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}
      - run: west update
      - run: west twister -T . --tag my-tag
      - uses: EnricoMi/publish-unit-test-result-action/linux@v2
        if: always()
        with:
          files: "**/twister.xml"
```

Run `nix flake check` in a separate job (the same action with `export-devshell`
off), the way these repos already keep check and build as separate jobs.
