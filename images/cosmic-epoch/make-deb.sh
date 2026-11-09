#!/bin/bash
# Turn the `just install` tree from trixie-build.sh into one .deb for Debian 13.
#
# Usage: make-deb.sh <staged-root> <packaging/debian dir> <output dir>
#
# This script only fails on tool errors. Policy problems (unexpected paths and
# so on) are written to package-summary.txt as "PROBLEM:" lines, and
# trixie-install-test.sh turns them into a red CI run. That way a packaging
# mistake costs a log entry, not another multi-hour compile.
set -euo pipefail

ROOT=$1
DEBDIR=$2
OUT=$3
SUMMARY="$OUT/package-summary.txt"

mkdir -p "$OUT"
: > "$SUMMARY"
note() { echo "$*" | tee -a "$SUMMARY"; }
problem() { note "PROBLEM: $*"; }

cd "$ROOT"

# 1. Only usr/ and etc/ belong in the package; anything else is left out.
for d in * .[!.]*; do
    [ -e "$d" ] || continue
    case "$d" in
        usr|etc) ;;
        *) problem "unexpected top-level path /$d left out of the package"
           rm -rf -- "$d" ;;
    esac
done

# 2. Same guard as main: never ship essential system binaries by accident.
for f in usr/bin/env usr/bin/bash usr/bin/sh usr/bin/dash usr/bin/python*; do
    if [ -e "$f" ]; then
        problem "removed /$f, which belongs to Debian itself"
        rm -f -- "$f"
    fi
done

# 3. Leave out cosmic-initial-setup's login-time autostart and its polkit rule.
# The autostart entry starts the first-boot wizard in every COSMIC session; the
# rule grants passwordless system changes to a "cosmic-initial-setup" user that
# Pop!_OS creates and this package does not. The wizard itself stays installed.
for f in etc/xdg/autostart/com.system76.CosmicInitialSetup.desktop \
         usr/share/polkit-1/rules.d/20-cosmic-initial-setup.rules; do
    if [ -e "$f" ]; then
        note "left out on purpose: /$f"
        rm -f -- "$f"
    fi
done
find etc usr -depth -type d -empty -delete 2>/dev/null || true

# 4. Find the ELF files and strip them, as dh_strip would.
mapfile -d '' elfs < <(
    find usr etc -type f -print0 2>/dev/null |
        while IFS= read -r -d '' f; do
            if [ "$(head -c 4 -- "$f" | od -An -c | tr -d ' ')" = '177ELF' ]; then
                printf '%s\0' "$f"
            fi
        done
)
if [ "${#elfs[@]}" -eq 0 ]; then
    echo "no ELF files under $ROOT" >&2
    exit 1
fi
before=$(du -cb -- "${elfs[@]}" | tail -n 1 | cut -f1)
strip --strip-unneeded -- "${elfs[@]}"
after=$(du -cb -- "${elfs[@]}" | tail -n 1 | cut -f1)
note "ELF files: ${#elfs[@]}, stripped from $((before / 1048576)) MiB to $((after / 1048576)) MiB"

# 5. Library dependencies from the binaries themselves, against trixie's
# shlibs/symbols files, instead of a hand-written list.
work=$(mktemp -d)
mkdir "$work/debian"
printf 'Source: cosmic-epoch-monorepo\n\nPackage: cosmic-epoch-monorepo\nArchitecture: amd64\n' \
    > "$work/debian/control"
shlibs=$(cd "$work" && dpkg-shlibdeps -O "${elfs[@]/#/$ROOT/}" | sed -n 's/^shlibs:Depends=//p')
rm -rf "$work"
if [ -z "$shlibs" ]; then
    echo "dpkg-shlibdeps produced no dependencies" >&2
    exit 1
fi

# 6. DEBIAN/ metadata.
mkdir -p DEBIAN
sed "s|@SHLIBS@|$shlibs|" "$DEBDIR/control" > DEBIAN/control
if grep -q '@[A-Z]*@' DEBIAN/control; then
    echo "unreplaced placeholder in control:" >&2
    grep '@[A-Z]*@' DEBIAN/control >&2
    exit 1
fi
size=$(du -sk --apparent-size usr etc 2>/dev/null | awk '{s += $1} END {print s}')
sed -i "/^Architecture:/a Installed-Size: $size" DEBIAN/control

if [ -d etc ]; then
    find etc -type f | sed 's|^|/|' | sort > DEBIAN/conffiles
    [ -s DEBIAN/conffiles ] || rm -f DEBIAN/conffiles
fi

pkg=$(sed -n 's/^Package: //p' DEBIAN/control)
ver=$(sed -n 's/^Version: //p' DEBIAN/control)
doc="usr/share/doc/$pkg"
mkdir -p "$doc"
gzip -9nc "$DEBDIR/changelog" > "$doc/changelog.Debian.gz"
cp "$DEBDIR/copyright" "$doc/copyright"
chmod 0644 "$doc/changelog.Debian.gz" "$doc/copyright"

find usr etc -type f -print0 2>/dev/null | sort -z | xargs -0 md5sum > DEBIAN/md5sums
chmod 0755 DEBIAN
chmod 0644 DEBIAN/*

# 7. Build.
deb="$OUT/${pkg}_${ver}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$deb"

{
    echo "== package"
    dpkg-deb -I "$deb"
    echo "== conffiles"
    cat DEBIAN/conffiles 2>/dev/null || echo none
    echo "== top-level directories"
    dpkg-deb -c "$deb" | awk '{print $6}' | cut -d/ -f2-4 | sort -u | grep -v '^$'
    echo "== file count: $(dpkg-deb -c "$deb" | grep -vc '/$')"
} >> "$SUMMARY"
cat "$SUMMARY"
