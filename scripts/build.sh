#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONF="$(cd "$SCRIPT_DIR/../config" && pwd)/pacman.conf"
MAKEPKG_CONF="$(cd "$SCRIPT_DIR/../config" && pwd)/makepkg.conf"

echo "==> SCRIPT_DIR=$SCRIPT_DIR"
echo "==> REPO_CONF=$REPO_CONF"
echo "==> MAKEPKG_CONF=$MAKEPKG_CONF"

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
    cp "$REPO_CONF" /etc/pacman.conf
    cp "$MAKEPKG_CONF" /etc/makepkg.conf
    pacman -Syu --noconfirm --needed base-devel

    source PKGBUILD
    local -a all_deps=()
    [[ -n "${makedepends[*]:-}" ]] && all_deps+=("${makedepends[@]}")
    [[ -n "${depends[*]:-}" ]] && all_deps+=("${depends[@]}")
    [[ -n "${checkdepends[*]:-}" ]] && all_deps+=("${checkdepends[@]}")
    if (( ${#all_deps[@]} > 0 )); then
        pacman -S --noconfirm --needed "${all_deps[@]}" || true
    fi

    chown -R builder:builder .
    su builder -c "makepkg -sf --noconfirm"
}

build_native() {
    echo "==> Building in native mode (makechrootpkg)"
    local chroot="/var/lib/archbuild/custom-aarch64"

    if [[ ! -f "$REPO_CONF" ]]; then
        echo "==> ERROR: pacman.conf not found at $REPO_CONF" >&2
        exit 1
    fi

    sudo mkdir -p "$chroot"

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
