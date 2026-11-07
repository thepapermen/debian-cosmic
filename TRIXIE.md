# COSMIC on Debian 13 "trixie": compile tests

## Full-stack result: all 28 steps built and `just install` passed

Run https://github.com/thepapermen/debian-cosmic/actions/runs/42324904725, commit
`dd5ce55`, cosmic-epoch `e98f8289a22f9e612feee7d4c6ba197782db154b` (`epoch-1.11.0`),
Debian 13.7, rustc 1.96.1 from trixie-backports, `just` 1.59.0, both downstream patches
applied, no other source patches. This covers compile, link and install into a staging
directory only. **No binary has ever been run.**

- `just install` produced 30 ELF files, and `ldd` found every library in the build
  container. A clean trixie system without the `-dev` packages has not been tested.
- Newest glibc symbol version required: `GLIBC_2.39`. Trixie has 2.41.
- Direct library dependencies: ld-linux-x86-64, libc, libdav1d.so.7, libdbus-1.so.3,
  libdisplay-info.so.2, libflatpak.so.0, libgbm.so.1, libgcc_s.so.1, libgio-2.0.so.0,
  libglib-2.0.so.0, libgobject-2.0.so.0, libgstapp-1.0.so.0, libgstpbutils-1.0.so.0,
  libgstreamer-1.0.so.0, libgsttag-1.0.so.0, libinput.so.10, libm, libpam.so.0,
  libpipewire-0.3.so.0, libpixman-1.so.0, libseat.so.1, libstdc++.so.6, libudev.so.1,
  libxkbcommon.so.0.
- The log has no cargo `Locking` lines, so no lockfile was visibly re-resolved. The
  recipes do not pass `--locked`, so nothing enforced this.
- Build time was 10018 s (2h47m). The same 27 steps took 18236 s in attempt 1 on the
  same reported 4 CPUs and 15 GB. The cause of that 1.8x difference is unknown, so
  plan for the slower figure.
- Disk peaked at 79 GB of 145 GB.
- Published: 0 releases, no Pages site. The only artifact is the 2.4 KB placeholder
  package, whose file list was checked and holds only the evidence text.

The trixie `just` 1.40.0 cannot parse four component justfiles, so `just` 1.59.0 was
built from crates.io with `--locked`.

The portal alone also passed in run
https://github.com/thepapermen/debian-cosmic/actions/runs/42324902347 (branch
`wip/trixie-portal`).


## Full-stack attempt 1: 27 of 28 steps passed, then the time budget ran out

Run https://github.com/thepapermen/debian-cosmic/actions/runs/42285941342, commit
`5ebd39f`, cosmic-epoch `e98f8289a22f9e612feee7d4c6ba197782db154b` (`epoch-1.11.0`),
Debian 13.7, rustc 1.96.1, `just` 1.59.0, both downstream patches applied.

- All 27 completed steps exited 0, and the log has no compiler error.
- `xdg-desktop-portal-cosmic` was stopped by this test's own 18900 s budget (exit 124)
  while still compiling. Whether it compiles was not shown by this run.
- `just install` did not run, so no installed files or library checks exist yet.
- The first 27 steps took 18236 s. Disk peaked at 78 GB of 145 GB.
- Slowest steps: cosmic-files 1728 s, cosmic-applets 1453 s, cosmic-settings 1258 s,
  cosmic-viewer 1033 s, cosmic-edit 981 s.

The next attempt raised the budget to 20700 s and passed; see the result above.

## cosmic-comp smoke test


**Result: `cosmic-comp` from tag `epoch-1.11.0` compiles and links on trixie**, with
Debian's Rust 1.96.1 from trixie-backports and no source patches. It passed on the
first CI run. This covers compile and link only: the binary has never been run.

This branch is a temporary smoke test, not packaging. Its Dockerfile produces no
usable package. Restore `images/cosmic-epoch/Dockerfile` from `main` before real
packaging work.

## What was tried

`images/cosmic-epoch/Dockerfile` was changed as follows:

- The base image is `debian:trixie`.
- `rustc`, `cargo` and `libstd-rust-*` are pinned to trixie-backports by name.
  Everything else comes from trixie main.
- It runs `just cosmic-comp/build-release --locked` in place of `just install`.
- It leaves out both downstream patches, which touch only cosmic-store and
  cosmic-notifications.

The workflow files are unchanged, because the token cannot push workflow changes. The
workflow requires a `/*.deb`, so the image carries a placeholder package that holds
only the evidence text. "Test Package Installation" therefore tested only that
placeholder.

Only the cosmic-epoch leg was built. The cosmic-utils leg was skipped by its path
filter.

**One failure before CI, in a local `docker build --target deps`:**
`apt-get install -t trixie-backports rustc cargo` also took `libcurl4t64` from
backports. That conflicted with `libcurl4-openssl-dev` from main, which
`libflatpak-dev` needs. A simulated `rustc/trixie-backports` install also took the
backported libcurl, so an APT pin by package name is used instead.

## Run

| | |
|---|---|
| Run | https://github.com/thepapermen/debian-cosmic/actions/runs/42276756772 (success) |
| Tested commit | `87e8d5f` |
| cosmic-epoch tag | `epoch-1.11.0` |
| cosmic-comp commit | `8cb1802caada438bb5cc7670dfabdaca5fad0502` |
| Base image | `debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6` (13.7) |
| Crates compiled | 465, with `cargo build --release --locked` |
| Compile time | 7m 43s on 4 CPUs; whole run about 15 minutes |
| Disk | `/build` 1.8 GB, cargo home 485 MB; 108 GB still free on the runner |

Memory was logged only before and after the compile, so peak use is unknown.

The runner reported a 145 GB overlay with 110 GB free before the compile. That is far
more than the 14 GB normally quoted for the free runner, so re-check it on the full
build.

## Versions used (from the CI log)

| Component | Version |
|---|---|
| rustc, cargo, libstd-rust-dev | 1.96.1+dfsg1-2~bpo13+1 (LLVM 22.1.8) |
| clang, libclang-dev | 19.1.7, 1:19.0-63 (`LIBCLANG_PATH=/usr/lib/llvm-19/lib`) |
| libc6-dev | 2.41-12+deb13u4 |
| libdisplay-info-dev | 0.2.0-2 (crate `libdisplay-info-sys` 0.3.0) |
| libinput-dev | 1.28.1-1+deb13u1 |
| libxkbcommon-dev | 1.7.0-2 |
| libwayland-dev, wayland-protocols | 1.23.1-3, 1.44-1 |
| libgbm-dev, libdrm-dev | 25.0.7-2+deb13u1, 2.4.124-2 |
| libseat-dev, libudev-dev, libpixman-1-dev | 0.9.1-1, 257.13-1~deb13u1, 0.44.0-3 |
| just | 1.40.0-1+b1 |

Only cargo, rustc, libstd-rust-dev and libstd-rust-1.96 came from backports.

## How the toolchain was confirmed

These all come from the CI log:

- The build fails unless `rustc` and `cargo` are in `/usr/bin` with a `~bpo13+` package
  version, and unless `rustup` is absent. These checks passed.
- `target/.rustc_info.json` and the binary's `.comment` section both record
  `rustc 1.96.1 (31fca3adb 2026-06-26)`.
- The log has no sign of a rustup channel sync, although cosmic-comp pins channel 1.93.

The binary needs `libdisplay-info.so.2`, and `ldd` resolves every library on trixie.
The newest glibc symbol version it requires is `GLIBC_2.39`; trixie has 2.41. Both
blockers of the published .deb (`GLIBC_2.43` and `libdisplay-info.so.3`) are absent
from this build.

## Published by this test

- **Releases:** none. The repository has 0 releases.
- **GitHub Pages:** no site. The `release` and `deploy-pages` jobs were both skipped.
- **GHCR:** nothing pushed, going by the log. The login steps were skipped, the build
  uses `push: false`, and no `docker push` ran. The token lacks `read:packages`, so
  the package list itself could not be checked.
- **Actions artifact:** `cosmic-epoch-deb` (2 KB, expires 2027-02-04). It holds only
  the placeholder package with the evidence text, which was verified by downloading it.

## Repository state

- The default branch is `wip/trixie-smoke`, so that the cron cannot run on `main`.
- `main` is unchanged at `d3dd6a8`.
- `build-packages.yml` is disabled, which stops its cron and its push trigger. It would
  otherwise run on this branch every Friday at 23:59 UTC, building both legs and
  cancelling any run in progress. Re-enable it with
  `gh workflow enable build-packages.yml -R thepapermen/debian-cosmic`.
- **Do not make `main` the default branch while the workflow is enabled.** A scheduled
  run there would pass the release gate.

## Still unproven

- That `cosmic-comp` runs at all, or works on real hardware with trixie's Mesa 25.0.7,
  libinput or libwayland. It was never started.
- The behaviour of the session as a whole, including the two downstream patches.
- Whether the build fits the 6-hour limit reliably. It took 2h47m in one run, and the
  other was on course for about 5h30m.
- Any working package: dependencies, install, upgrade, or removal.

## Proposed next milestones

Milestones 2 and 3 need workflow changes, because the workflow installs into
`debian:testing` and its release job targets `unstable`. The current token cannot push
those changes, so that needs a decision from the owner.

1. Done: full-stack build on trixie, `just install` with the downstream patches.
2. Real packaging: use `dpkg-shlibdeps` and correct trixie dependencies (the current
   control file names `libdisplay-info3`, but this build needs `libdisplay-info.so.2`).
   Test the install in `debian:trixie`.
3. A separate trixie APT suite, kept apart from `unstable`.
4. Pin actions to commit hashes.
5. Run `cargo audit` on the lockfiles.
6. Sign the repository locally, so that no signing key lives on GitHub.
