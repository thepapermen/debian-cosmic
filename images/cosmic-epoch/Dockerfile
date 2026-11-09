# syntax=docker/dockerfile:1
#
# TRIXIE .DEB TEST - branch wip/trixie-deb - NOT A RELEASE.
# Builds all of COSMIC from tag epoch-1.11.0 on Debian 13 "trixie" with the
# Debian-built Rust toolchain from trixie-backports (stages 1-2, unchanged from
# the passing compile test on wip/trixie-full), then packages the `just install`
# tree as one .deb with dependencies generated for trixie (stage 3).
# CI installs it in a clean debian:trixie container: trixie-install-test.sh.
# The sysext stage from main is not built here.

# Stage 1: build dependencies (no compiling; safe to build locally with --target deps)
FROM debian:trixie AS deps

ENV DEBIAN_FRONTEND=noninteractive

# 1. rustc and cargo come from trixie-backports, pinned by name so that nothing
# else does. `apt-get -t trixie-backports` and `rustc/trixie-backports` are both
# wrong here: they also take libcurl4t64, its libngtcp2/libnghttp3 and (with -t)
# linux-libc-dev from backports, and the backported libcurl4t64 then conflicts with
# libcurl4-openssl-dev from main, which libflatpak-dev needs. Everything except the
# Rust toolchain stays on trixie main, so a pass says something about trixie itself.
RUN echo 'deb http://deb.debian.org/debian trixie-backports main' \
        > /etc/apt/sources.list.d/trixie-backports.list && \
    printf '%s\n' \
        'Package: rustc cargo libstd-rust-dev libstd-rust-*' \
        'Pin: release n=trixie-backports' \
        'Pin-Priority: 990' \
        > /etc/apt/preferences.d/rust-from-backports && \
    apt-get update && \
    apt-get install -y \
    rustc cargo \
    build-essential git pkg-config \
    libpipewire-0.3-dev libspa-0.2-dev libwayland-dev libxkbcommon-dev \
    libinput-dev libseat-dev libudev-dev libgbm-dev libdrm-dev \
    libdbus-1-dev libpam0g-dev libfontconfig-dev libfreetype-dev \
    libpolkit-gobject-1-dev libgudev-1.0-dev libglib2.0-dev \
    libjson-glib-dev libpulse-dev libasound2-dev libssl-dev \
    libflatpak-dev libarchive-dev libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev clang llvm-dev cmake \
    libpixman-1-dev libwayland-bin libdisplay-info-dev libxcb-xinput-dev libdav1d-dev \
    wayland-protocols extra-cmake-modules scdoc sed make libclang-dev \
    gtk-update-icon-cache hicolor-icon-theme bsdextrautils nasm \
    && rm -rf /var/lib/apt/lists/*

# 2. Rust/Cargo build configuration
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=$CARGO_HOME/bin:$PATH
ENV CARGO_TERM_COLOR=never
ENV CARGO_PROFILE_RELEASE_LTO=thin
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
ENV CARGO_PROFILE_RELEASE_PANIC=abort
ENV LIBCLANG_PATH=/usr/lib/llvm-19/lib

# 3. Fail early unless the toolchain really is Debian's backport.
# Debian's cargo has no rustup proxy, so cosmic-comp's rust-toolchain.toml
# (channel 1.93) is ignored; these checks turn that assumption into a fact.
RUN set -eux; \
    cat /etc/debian_version; \
    if command -v rustup; then echo 'unexpected rustup' >&2; exit 1; fi; \
    test "$(command -v rustc)" = /usr/bin/rustc; \
    test "$(command -v cargo)" = /usr/bin/cargo; \
    dpkg-query -W -f='${Version}' rustc | grep -q '~bpo13+'; \
    dpkg-query -W -f='${Version}' cargo | grep -q '~bpo13+'; \
    test -e "$LIBCLANG_PATH/libclang.so"; \
    rustc -vV; \
    cargo -vV; \
    clang --version; \
    echo '== packages installed from trixie-backports'; \
    dpkg-query -W -f='${Package} ${Version}\n' | grep -F '~bpo'; \
    echo '== system library versions'; \
    dpkg-query -W -f='${Package} ${Version}\n' \
        libc6-dev libclang-dev libdisplay-info-dev libdrm-dev libgbm-dev \
        libinput-dev libpixman-1-dev libseat-dev libudev-dev libwayland-dev \
        libxkbcommon-dev wayland-protocols

# 3b. Trixie's just 1.40.0 cannot parse the `::` module syntax used by the
# justfiles of cosmic-app-library, cosmic-initial-setup, cosmic-launcher and
# cosmic-settings-daemon at epoch-1.11.0. Build forky's version from crates.io with
# the Debian toolchain; --locked holds its dependencies to its own Cargo.lock.
RUN cargo install just --version 1.59.0 --locked --root /usr/local && \
    test "$(command -v just)" = /usr/local/bin/just && \
    just --version | grep -qx 'just 1.59.0' && \
    if dpkg-query -W just 2>/dev/null; then echo 'unexpected apt just' >&2; exit 1; fi

# Stage 2: compile the whole desktop
FROM deps AS builder

WORKDIR /build

COPY patches/ /patches/
COPY trixie-build.sh /usr/local/bin/trixie-build.sh

# Same checkout and downstream patches as main.
RUN git config --global --add safe.directory /build && \
    git clone --recursive --branch epoch-1.11.0 https://github.com/pop-os/cosmic-epoch.git . && \
    patch -p1 < /patches/0001-cosmic-store-packagekit-feature.patch && \
    patch -p1 < /patches/0002-cosmic-notifications-sigpipe-guard-and-libc-dep.patch && \
    git rev-parse HEAD

# 4. Build every component, then `just install`. One failing component does not
# stop the others, and the build still fails at the end. Evidence goes to the log
# and /compile-evidence.txt; the installed tree in /export goes to stage 3.
RUN date -u && nproc && free -g && df -h / && \
    trixie-build.sh && \
    date -u && free -g && df -h /

# Stage 3: package. Same image as the build (trixie + the -dev packages), so
# dpkg-shlibdeps resolves every library against trixie's own shlibs/symbols.
FROM deps AS deb-packager
COPY --from=builder /export /pkg
COPY packaging/debian /packaging/debian
COPY make-deb.sh /usr/local/bin/make-deb.sh
RUN make-deb.sh /pkg /packaging/debian /out

# Final stage: just for artifact extraction (CI copies /*.deb and /*.txt)
FROM busybox
COPY --from=deb-packager /out/ /
COPY --from=builder /compile-evidence.txt /compile-evidence.txt

LABEL org.opencontainers.image.source="https://github.com/thepapermen/debian-cosmic"
LABEL org.opencontainers.image.description="TEST .deb of COSMIC epoch-1.11.0 for Debian trixie. Not a release."
LABEL org.opencontainers.image.licenses="GPL-3.0"

CMD ["sh"]
