#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> SCRIPT_DIR=$SCRIPT_DIR"

chown -R builder:builder .

# Evaluate PKGBUILD metadata as the unprivileged build user. This avoids
# executing package-provided shell code as root before makepkg starts.
mapfile -t all_deps < <(
    su -s /bin/bash builder -c 'makepkg --printsrcinfo' |
        awk -F ' = ' '$1 ~ /^[[:space:]]*(makedepends|depends|checkdepends)$/ { print $2 }' |
        sort -u
)

if (( ${#all_deps[@]} > 0 )); then
    # Keep the container's installed base immutable while refreshing repository
    # metadata so newly published internal dependencies can be resolved.
    pacman -Sy --noconfirm

    # Only install dependencies that are not already satisfied. Passing
    # installed packages to `pacman -S --needed` would still upgrade them when
    # the repository is newer than the container, which can break packages
    # pinned to an exact version (e.g. gcc requires gcc-libs=<same version>).
    mapfile -t missing_deps < <(pacman -T "${all_deps[@]}" || true)
    if (( ${#missing_deps[@]} > 0 )); then
        pacman -S --noconfirm --needed "${missing_deps[@]}"
    fi
fi

su builder -c "makepkg -sf --noconfirm"

echo "==> Build complete. Artifacts:"
ls -lh ./*.pkg.tar.zst 2>/dev/null || echo "  (no packages found)"
