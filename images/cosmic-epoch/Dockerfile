# syntax=docker/dockerfile:1
#
# TEMPORARY SMOKE TEST - branch wip/trixie-smoke - NOT A PACKAGING RECIPE.
# Only question answered: does cosmic-comp from tag epoch-1.11.0 compile on
# Debian 13 "trixie" with the Debian-built Rust toolchain from trixie-backports?
# The sysext and real .deb stages are removed on purpose; see TRIXIE.md.
# Restore this file from main before doing any real packaging work.
# The workflow cancels an in-progress run on any new push to this branch.

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
    build-essential git just pkg-config \
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
        libc6-dev just libclang-dev libdisplay-info-dev libdrm-dev libgbm-dev \
        libinput-dev libpixman-1-dev libseat-dev libudev-dev libwayland-dev \
        libxkbcommon-dev wayland-protocols

# Stage 2: compile cosmic-comp only
FROM deps AS builder

WORKDIR /build

# Same checkout as main. The downstream patches stay out: 0001 edits a
# cosmic-store line in the epoch justfile, 0002 edits cosmic-notifications, and
# neither touches cosmic-comp.
RUN git config --global --add safe.directory /build && \
    git clone --recursive --branch epoch-1.11.0 https://github.com/pop-os/cosmic-epoch.git . && \
    git -C cosmic-comp rev-parse HEAD

# 4. Build cosmic-comp only, in place of `just install`. --locked holds the
# dependency versions to upstream's Cargo.lock.
RUN date -u && nproc && free -g && df -h / && \
    just cosmic-comp/build-release --locked && \
    date -u && free -g && df -h / && du -sh /build /build/cosmic-comp/target "$CARGO_HOME"

# 5. Record what was built and how. The build was only proven to compile and
# link; the binary is not run here and does not leave this stage.
RUN set -eu; \
    bin=cosmic-comp/target/release/cosmic-comp; \
    { \
        echo "NOT A RELEASE. Compile-only smoke test evidence from wip/trixie-smoke."; \
        echo "== cosmic-comp commit"; git -C cosmic-comp rev-parse HEAD; \
        echo "== debian_version"; cat /etc/debian_version; \
        echo "== rustc -vV"; rustc -vV; \
        echo "== cargo -vV"; cargo -vV; \
        echo "== rustc recorded by cargo in target/.rustc_info.json"; \
        grep -o 'rustc [0-9][^\\"]*' cosmic-comp/target/.rustc_info.json | sort -u; \
        echo "== rustc recorded in the binary's .comment section"; \
        readelf -p .comment "$bin"; \
        echo "== packages from trixie-backports"; \
        dpkg-query -W -f='${Package} ${Version}\n' | grep -F '~bpo'; \
        echo "== system library versions"; \
        dpkg-query -W -f='${Package} ${Version}\n' \
            libc6-dev just libclang-dev libdisplay-info-dev libdrm-dev libgbm-dev \
            libinput-dev libpixman-1-dev libseat-dev libudev-dev libwayland-dev \
            libxkbcommon-dev wayland-protocols; \
        echo "== binary"; ls -l "$bin"; sha256sum "$bin"; \
        echo "== NEEDED"; readelf -d "$bin" | grep NEEDED; \
        echo "== ldd"; ldd "$bin"; \
        echo "== newest GLIBC symbol version required"; \
        objdump -T "$bin" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n 1; \
        echo "== end of evidence"; \
    } | tee /compile-evidence.txt; \
    grep -qx '== end of evidence' /compile-evidence.txt; \
    if grep -F 'not found' /compile-evidence.txt; then exit 1; fi

# Stage 3: placeholder. The unmodified CI workflow insists on a /*.deb that it can
# extract, install and upload. This one holds only the evidence text and no COSMIC
# file, so a green run means "compiled" and nothing more.
FROM debian:trixie AS placeholder
COPY --from=builder /compile-evidence.txt /pkg/usr/share/doc/not-a-release-trixie-smoke/compile-evidence.txt
RUN mkdir -p /pkg/DEBIAN && \
    { \
        echo 'Package: not-a-release-trixie-smoke'; \
        echo 'Version: 0~smoke'; \
        echo 'Architecture: all'; \
        echo 'Maintainer: wip/trixie-smoke <noreply@example.invalid>'; \
        echo 'Section: misc'; \
        echo 'Priority: optional'; \
        echo 'Description: NOT A RELEASE - cosmic-comp compile evidence only'; \
        echo ' Placeholder for a temporary CI smoke test. Contains no COSMIC software.'; \
    } > /pkg/DEBIAN/control && \
    dpkg-deb --build /pkg /not-a-release-trixie-smoke_0~smoke_all.deb

# Final stage: just for artifact extraction
FROM busybox
COPY --from=placeholder /not-a-release-trixie-smoke_0~smoke_all.deb /
COPY --from=builder /compile-evidence.txt /compile-evidence.txt

LABEL org.opencontainers.image.source="https://github.com/thepapermen/debian-cosmic"
LABEL org.opencontainers.image.description="TEMPORARY cosmic-comp compile smoke test on Debian trixie. Not a release."
LABEL org.opencontainers.image.licenses="GPL-3.0"

CMD ["sh"]
