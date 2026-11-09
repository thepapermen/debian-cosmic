#!/bin/bash
# Install test for the trixie .deb, run as root in a clean debian:trixie container:
#   docker run --rm -v "$DIST:/dist" -v "$PWD/images/cosmic-epoch:/t:ro" \
#       debian:trixie bash /t/trixie-install-test.sh /dist
#
# What a pass means: the package installs on trixie with its Depends only, every
# binary links against trixie's libraries without missing libraries or symbols,
# every launcher points at an installed program, and the package removes
# cleanly. It does NOT mean the desktop works: nothing here has a GPU, a seat
# or a display. That needs real hardware or a VM.
set -u
export DEBIAN_FRONTEND=noninteractive

DIST=${1:-/dist}
REPORT="$DIST/install-test.txt"
: > "$REPORT"
fails=0
say() { echo "$*" | tee -a "$REPORT"; }
fail() { say "FAIL: $*"; fails=$((fails + 1)); }

debs=("$DIST"/*.deb)
if [ "${#debs[@]}" -ne 1 ] || [ ! -f "${debs[0]}" ]; then
    fail "expected exactly one .deb in $DIST, found: ${debs[*]}"
    exit 1
fi
deb=${debs[0]}
pkg=$(dpkg-deb -f "$deb" Package)

say "== system"
say "debian_version $(cat /etc/debian_version)"
say "package $(basename "$deb")"

say "== problems recorded while packaging"
if [ -f "$DIST/package-summary.txt" ]; then
    if grep '^PROBLEM:' "$DIST/package-summary.txt" | tee -a "$REPORT" | grep -q .; then
        fail "make-deb.sh recorded problems (above)"
    else
        say none
    fi
else
    fail "package-summary.txt missing"
fi

say "== install with Depends only"
apt-get update -qq
if apt-get install -y --no-install-recommends "$deb" > /tmp/apt.log 2>&1; then
    say "installed $(dpkg-query -W -f='${Version}' "$pkg")"
    say "packages pulled in: $(grep -c '^Setting up ' /tmp/apt.log)"
else
    tail -n 40 /tmp/apt.log | tee -a "$REPORT"
    fail "apt-get install"
    say "== result: $fails failure(s)"
    exit 1
fi

say "== Recommends and Suggests exist in trixie"
for field in Recommends Suggests; do
    dpkg-deb -f "$deb" "$field" | tr ',|' '\n\n' | sed 's/(.*)//; s/ //g' | grep . |
        while read -r p; do
            if [ -z "$(apt-cache policy "$p" | sed -n 's/ *Candidate: //p' | grep -v '(none)')" ]; then
                echo "$field $p"
            fi
        done
done > /tmp/missing.txt
if [ -s /tmp/missing.txt ]; then
    while read -r l; do fail "not in trixie: $l"; done < /tmp/missing.txt
else
    say ok
fi

# Tools for the checks below, installed after the dependency check on purpose.
apt-get install -y --no-install-recommends binutils desktop-file-utils > /dev/null 2>&1 ||
    fail "could not install binutils/desktop-file-utils"

mapfile -t files < <(dpkg -L "$pkg" | while read -r f; do [ -f "$f" ] && [ ! -L "$f" ] && echo "$f"; done)
elfs=()
for f in "${files[@]}"; do
    [ "$(head -c 4 -- "$f" | od -An -c | tr -d ' ')" = '177ELF' ] && elfs+=("$f")
done

say "== paths outside /usr and /etc"
outside=$(printf '%s\n' "${files[@]}" | grep -vE '^/(usr|etc)/' || true)
if [ -n "$outside" ]; then
    echo "$outside" | tee -a "$REPORT"
    fail "files outside /usr and /etc"
else
    say none
fi

say "== files shipped in /etc"
etcfiles=$(printf '%s\n' "${files[@]}" | grep '^/etc/' || true)
say "${etcfiles:-none}"

say "== libraries and symbols (ldd -r), ${#elfs[@]} ELF files"
[ "${#elfs[@]}" -gt 0 ] || fail "no ELF files installed"
bad=0
for f in "${elfs[@]}"; do
    out=$(ldd -r "$f" 2>&1 | grep -E 'not found|undefined symbol' || true)
    if [ -n "$out" ]; then
        echo "$f:" | tee -a "$REPORT"
        echo "$out" | sed 's/^/    /' | tee -a "$REPORT"
        fail "unresolved libraries or symbols in $f"
        bad=1
    fi
done
[ "$bad" -eq 0 ] && say ok

say "== launchers point at installed programs"
mapfile -t desktops < <(printf '%s\n' "${files[@]}" | grep -E '\.desktop$')
for d in "${desktops[@]}"; do
    grep -E '^(Exec|TryExec)=' "$d" | cut -d= -f2- | sort -u | while read -r cmd; do
        prog=${cmd%% *}
        case "$prog" in
            /*) [ -x "$prog" ] || echo "$d -> $prog" ;;
            *) command -v "$prog" > /dev/null || echo "$d -> $prog" ;;
        esac
    done
done > /tmp/badexec.txt
if [ -s /tmp/badexec.txt ]; then
    while read -r l; do fail "launcher target missing: $l"; done < /tmp/badexec.txt
else
    say "ok (${#desktops[@]} .desktop files)"
fi
say "-- desktop-file-validate (informational)"
desktop-file-validate "${desktops[@]}" 2>&1 | grep -v '^$' | head -n 40 | tee -a "$REPORT" || true

say "== session entry"
if [ -f /usr/share/wayland-sessions/cosmic.desktop ]; then
    grep -E '^(Name|Exec|DesktopNames)=' /usr/share/wayland-sessions/cosmic.desktop | tee -a "$REPORT"
else
    fail "/usr/share/wayland-sessions/cosmic.desktop missing"
fi

say "== first-login wizard"
f=/etc/xdg/autostart/com.system76.CosmicInitialSetup.desktop
if [ -e "$f" ]; then say "present: $f"; else fail "$f is missing"; fi
f=/usr/share/polkit-1/rules.d/20-cosmic-initial-setup.rules
if [ -e "$f" ]; then fail "$f is installed"; else say "absent (on purpose): $f"; fi

say "== libraries the binaries may load at run time (informational)"
# Rust graphics stacks dlopen EGL, Vulkan and similar instead of linking them,
# so dpkg-shlibdeps cannot see them. List what the binaries mention and whether
# this minimal install has it.
for f in "${elfs[@]}"; do
    strings -a "$f" | grep -oE '^lib[A-Za-z0-9_+-]+\.so(\.[0-9]+)*$'
done | sort -u | while read -r lib; do
    if ldconfig -p | grep -qF " $lib "; then
        echo "  present  $lib"
    else
        echo "  absent   $lib"
    fi
done | tee -a "$REPORT"

say "== start each program once without a display (informational, 5s each)"
for f in "${elfs[@]}"; do
    case "$f" in /usr/bin/*|/usr/libexec/*) ;; *) continue ;; esac
    # Output to a file, not a pipe: a program that forks would hold a pipe open.
    (cd /tmp && env -i PATH=/usr/bin:/bin HOME=/tmp timeout -k 2 5 "$f" --help \
        > /tmp/run.out 2>&1 < /dev/null)
    status=$?
    out=$(head -n 1 /tmp/run.out | tr -d '\r')
    printf '  %-45s exit=%-3s %s\n' "$f" "$status" "${out:0:80}" | tee -a "$REPORT"
done

say "== remove and purge"
if apt-get purge -y "$pkg" > /tmp/purge.log 2>&1; then
    left=$(printf '%s\n' "${files[@]}" | while read -r f; do [ -e "$f" ] && echo "$f"; done)
    if [ -n "$left" ]; then
        echo "$left" | tee -a "$REPORT"
        fail "files left after purge"
    else
        say "ok, no files left"
    fi
else
    tail -n 20 /tmp/purge.log | tee -a "$REPORT"
    fail "apt-get purge"
fi

say "== result: $fails failure(s)"
[ "$fails" -eq 0 ]
