# .repo-infra

Build infrastructure for the **aarch64-addons** Arch Linux package repository.

This repo centralizes all CI/CD workflows, build scripts, and configuration. Individual `pkg-xxx` repos contain only PKGBUILD files — no workflow files needed.

## Repository Structure

```
.github/workflows/
  build-package.yml     # Build a single package (workflow_dispatch / workflow_call)
  build-all.yml         # Batch build all registered packages
  detect-updates.yml    # Cron: scan pkg-xxx repos for new commits, trigger builds
  build-container.yml   # Build & push the aarch64 build environment image to GHCR
scripts/
  build.sh              # Build script (auto-detects container vs native chroot)
  detect-updates.sh     # Update detection logic
  sign-package.sh       # GPG sign all .pkg.tar.zst in cwd
config/
  pacman.conf           # pacman config for build environment
  makepkg.conf          # makepkg config
  packages.json         # Package registry (name, repo, arch, runner, timeout)
state/
  build-state.json      # Last-built commit SHA per package (auto-maintained)
Containerfile           # aarch64 Arch Linux build environment image
```

## Build Modes

| Runner | Mode | Isolation |
|--------|------|-----------|
| `ubuntu-24.04-arm` (GitHub) | Container + `makepkg` | Docker (fresh each run) |
| `self-hosted` (Arch Linux) | Native `makechrootpkg` | systemd-nspawn clean chroot |

## Adding a New Package

1. Create `pkg-<name>` repo in the org with a `PKGBUILD`
2. Register it in `config/packages.json`
3. Manually trigger `build-package.yml` or wait for `detect-updates.yml`

## Required Org Secrets

| Secret | Description |
|--------|-------------|
| `GPG_PRIVATE_KEY` | GPG private key (base64-encoded) |
| `GPG_PASSPHRASE` | GPG passphrase |
| `REPO_DISPATCH_TOKEN` | Fine-grained PAT with `contents:write` + `actions:write` for org repos |
