#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_CONF="$SCRIPT_DIR/../config/pacman.conf"
MAKEPKG_CONF="$SCRIPT_DIR/../config/makepkg.conf"

detect_environment() {
    if [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
        echo "container"
    elif command -v makechrootpkg &>/dev/null; then
        echo "native"
    else
        echo "container"
    fi
}

build_container() {
    echo "==> Building in container mode (makepkg)"
    sudo cp "$REPO_CONF" /etc/pacman.conf
    sudo cp "$MAKEPKG_CONF" /etc/makepkg.conf
    sudo pacman -Syu --noconfirm --needed base-devel

    # Install declared dependencies
    source PKGBUILD
    local -a all_deps=()
    [[ -n "${makedepends[*]:-}" ]] && all_deps+=("${makedepends[@]}")
    [[ -n "${depends[*]:-}" ]] && all_deps+=("${depends[@]}")
    [[ -n "${checkdepends[*]:-}" ]] && all_deps+=("${checkdepends[@]}")
    if (( ${#all_deps[@]} > 0 )); then
        sudo pacman -S --noconfirm --needed "${all_deps[@]}" || true
    fi

    makepkg -sf --noconfirm
}

build_native() {
    echo "==> Building in native mode (makechrootpkg)"
    local chroot="/var/lib/archbuild/custom-aarch64"

    if [[ ! -d "$chroot/root" ]]; then
        echo "==> Creating clean chroot..."
        sudo mkarchroot -C "$REPO_CONF" -M "$MAKEPKG_CONF" "$chroot/root" base-devel
    else
        echo "==> Updating existing chroot..."
        sudo arch-nspawn "$chroot/root" pacman -Syu --noconfirm
    fi

    makechrootpkg -c -r "$chroot"
}

ENV=$(detect_environment)
echo "==> Detected environment: $ENV"

case "$ENV" in
    container) build_container ;;
    native)    build_native ;;
esac

echo "==> Build complete. Artifacts:"
ls -lh ./*.pkg.tar.zst 2>/dev/null || echo "  (no packages found)"
