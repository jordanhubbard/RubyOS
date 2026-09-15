FROM python:3.14-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    libc6-dev-arm64-cross linux-libc-dev-arm64-cross \
    libc6-dev-amd64-cross linux-libc-dev-amd64-cross \
    nasm grub-common xorriso mtools e2fsprogs \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# grub-pc-bin is an architecture-independent collection of boot modules even
# though Debian labels its package amd64. Extract the payload without adding a
# foreign dpkg architecture to the ARM64 builder.
ARG GRUB_PC_BIN_VERSION=2.06-13+deb12u2
ARG GRUB_PC_BIN_SHA256=db6aced5a89f02e10e150140b4df9621196f311c26203baf8558b4c6808e1298
RUN curl -fsSL -o /tmp/grub-pc-bin.deb \
        "https://deb.debian.org/debian/pool/main/g/grub2/grub-pc-bin_${GRUB_PC_BIN_VERSION}_amd64.deb" \
    && echo "${GRUB_PC_BIN_SHA256}  /tmp/grub-pc-bin.deb" | sha256sum -c - \
    && dpkg-deb -x /tmp/grub-pc-bin.deb / \
    && rm /tmp/grub-pc-bin.deb

RUN ln -s /usr/bin/x86_64-linux-gnu-gcc /usr/local/bin/x86_64-elf-gcc \
    && ln -s /usr/bin/x86_64-linux-gnu-ld /usr/local/bin/x86_64-elf-ld \
    && ln -s /usr/bin/x86_64-linux-gnu-ar /usr/local/bin/x86_64-elf-ar \
    && ln -s /usr/bin/x86_64-linux-gnu-ranlib /usr/local/bin/x86_64-elf-ranlib \
    && ln -s /usr/bin/aarch64-linux-gnu-gcc /usr/local/bin/aarch64-elf-gcc \
    && ln -s /usr/bin/aarch64-linux-gnu-ld /usr/local/bin/aarch64-elf-ld \
    && ln -s /usr/bin/aarch64-linux-gnu-ar /usr/local/bin/aarch64-elf-ar \
    && ln -s /usr/bin/aarch64-linux-gnu-ranlib /usr/local/bin/aarch64-elf-ranlib

WORKDIR /work
