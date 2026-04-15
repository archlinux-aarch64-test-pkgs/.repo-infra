# Stage 1: Extract pre-downloaded aarch64 rootfs
#
# Usage:
#   1. Download rootfs to build context:
#      curl -L -o rootfs.tar.zst \
#        "https://arch-linux-repo.drzee.net/arch/tarballs/os/aarch64/archlinux-bootstrap-<DATE>-aarch64.tar.zst"
#   2. Build:
#      podman build -f Containerfile -t ghcr.io/archlinux-aarch64-test-pkgs/build-env:latest .

FROM docker.io/arm64v8/ubuntu:24.04 AS extractor

RUN apt-get update && \
    apt-get install -y --no-install-recommends zstd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY rootfs.tar.zst /tmp/rootfs.tar.zst
RUN mkdir /rootfs && \
    tar --zstd -xf /tmp/rootfs.tar.zst -C /rootfs && \
    rm /tmp/rootfs.tar.zst

# Stage 2: Build the final image from extracted root.aarch64/
FROM scratch
COPY --from=extractor /rootfs/root.aarch64/ /

COPY config/pacman.conf /etc/pacman.conf
COPY config/makepkg.conf /etc/makepkg.conf

RUN pacman-key --init && \
    curl -fsSL -o /tmp/drzee-repo.key \
      https://arch-linux-repo.drzee.net/arch/extra/os/aarch64/public.key && \
    pacman-key --add /tmp/drzee-repo.key && \
    pacman-key --lsign-key key@drzee.net && \
    rm /tmp/drzee-repo.key && \
    pacman -Syu --noconfirm base-devel git jq && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

RUN useradd -m builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

CMD ["/bin/bash"]
