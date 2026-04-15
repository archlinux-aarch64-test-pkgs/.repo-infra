#!/bin/bash
set -euo pipefail

# Signs all .pkg.tar.zst files in the current directory.
# Expects GPG_PASSPHRASE environment variable to be set.

if [[ -z "${GPG_PASSPHRASE:-}" ]]; then
    echo "ERROR: GPG_PASSPHRASE is not set" >&2
    exit 1
fi

shopt -s nullglob
pkgs=(*.pkg.tar.zst)
shopt -u nullglob

if (( ${#pkgs[@]} == 0 )); then
    echo "ERROR: No .pkg.tar.zst files found in $(pwd)" >&2
    exit 1
fi

for pkg in "${pkgs[@]}"; do
    echo "==> Signing $pkg"
    gpg --batch --pinentry-mode loopback \
        --passphrase "$GPG_PASSPHRASE" \
        --detach-sign "$pkg"
    echo "  → ${pkg}.sig"
done

echo "==> All packages signed."
