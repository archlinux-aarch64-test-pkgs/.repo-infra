# Stage 1: Extract a verified aarch64 rootfs from the build context.
#
# CI downloads and verifies rootfs.tar.zst before invoking the image build. For
# local builds, provide the same verified archive in the build context.

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
    pacman -Syu --noconfirm --needed base-devel curl git gnupg jq && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

RUN useradd -m builder

CMD ["/bin/bash"]
