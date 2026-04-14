# Stage 1: Download and extract aarch64 rootfs from Arch Linux Ports (drzee.net)
FROM arm64v8/ubuntu:24.04 AS fetcher

ARG ROOTFS_DATE=2026.04.01
ARG ROOTFS_URL=https://arch-linux-repo.drzee.net/arch/tarballs/os/aarch64/archlinux-bootstrap-${ROOTFS_DATE}-aarch64.tar.zst

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl zstd && \
    curl -L -o /tmp/rootfs.tar.zst "$ROOTFS_URL" && \
    mkdir /rootfs && \
    tar --zstd -xf /tmp/rootfs.tar.zst -C /rootfs && \
    rm /tmp/rootfs.tar.zst && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 2: Build the final image from extracted root.aarch64/
FROM scratch
COPY --from=fetcher /rootfs/root.aarch64/ /

COPY config/pacman.conf /etc/pacman.conf
COPY config/makepkg.conf /etc/makepkg.conf

RUN pacman-key --init && \
    pacman -Syu --noconfirm base-devel git jq && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

RUN useradd -m builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

CMD ["/bin/bash"]
