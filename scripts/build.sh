#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONF="$(cd "$SCRIPT_DIR/../config" && pwd)/pacman.conf"
MAKEPKG_CONF="$(cd "$SCRIPT_DIR/../config" && pwd)/makepkg.conf"

echo "==> SCRIPT_DIR=$SCRIPT_DIR"
echo "==> REPO_CONF=$REPO_CONF"
echo "==> MAKEPKG_CONF=$MAKEPKG_CONF"

cp "$REPO_CONF" /etc/pacman.conf
cp "$MAKEPKG_CONF" /etc/makepkg.conf

curl -fsSL -o /tmp/drzee-repo.key \
  https://arch-linux-repo.drzee.net/arch/extra/os/aarch64/public.key
pacman-key --add /tmp/drzee-repo.key
pacman-key --lsign-key key@drzee.net
rm /tmp/drzee-repo.key

pacman -Syu --noconfirm --needed base-devel

source PKGBUILD
declare -a all_deps=()
[[ -n "${makedepends[*]:-}" ]] && all_deps+=("${makedepends[@]}")
[[ -n "${depends[*]:-}" ]] && all_deps+=("${depends[@]}")
[[ -n "${checkdepends[*]:-}" ]] && all_deps+=("${checkdepends[@]}")
if (( ${#all_deps[@]} > 0 )); then
    pacman -S --noconfirm --needed "${all_deps[@]}" || true
fi

chown -R builder:builder .
su builder -c "makepkg -sf --noconfirm"

echo "==> Build complete. Artifacts:"
ls -lh ./*.pkg.tar.zst 2>/dev/null || echo "  (no packages found)"
