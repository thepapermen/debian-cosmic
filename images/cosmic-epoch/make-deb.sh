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
trap 'echo "make-deb.sh: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

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

# 3. Leave out cosmic-initial-setup's polkit rule. It grants passwordless system
# changes to the temporary "cosmic-initial-setup" user of Pop!_OS's installer
# (OEM) mode, which upstream's postinst creates and this package does not: on
# Debian the installer has already created the real user. The per-user
# first-login wizard (the /etc/xdg/autostart entry) stays; it runs once per user
# and then writes ~/.config/cosmic-initial-setup-done.
f=usr/share/polkit-1/rules.d/20-cosmic-initial-setup.rules
if [ -e "$f" ]; then
    note "left out on purpose: /$f"
    rm -f -- "$f"
fi
find etc usr -depth -type d -empty -delete 2>/dev/null || true

# Files from upstream's Debian packaging that `just install` does not install
# (greeter units, greetd config, PAM file); see packaging/debian/files/README.
if [ -d "$DEBDIR/files" ]; then
    (cd "$DEBDIR/files" && find . -type f ! -name README -print0) |
        while IFS= read -r -d '' f; do
            if [ -e "$f" ]; then
                problem "/${f#./} is installed by just install too; packaging copy not used"
            else
                install -D -m 0644 "$DEBDIR/files/$f" "$f"
                note "added from packaging: /${f#./}"
            fi
        done
fi

# As dh_fixperms and dh_link would: D-Bus policy files are data (upstream
# installs the greeter's with mode 0755), and links inside the package are
# relative (the applets are links to /usr/bin/cosmic-applets).
if [ -d usr/share/dbus-1 ]; then
    find usr/share/dbus-1 -type f -perm /111 -exec chmod 0644 {} +
fi
while IFS= read -r -d '' l; do
    t=$(readlink -- "$l")
    case "$t" in
        /usr/*|/etc/*)
            ln -sfn -- "$(realpath -ms --relative-to="$(dirname -- "$l")" "${t#/}")" "$l"
            note "made relative: /$l -> $(readlink -- "$l")" ;;
    esac
done < <(find usr etc -type l -print0 2>/dev/null)

# The top-level directories that still exist. Never name a missing one below:
# with pipefail, `du usr etc` fails on a missing etc/ (that broke the first
# CI run, after step 3 had emptied etc/).
dirs=()
for d in usr etc; do
    [ -d "$d" ] && dirs+=("$d")
done
if [ "${#dirs[@]}" -eq 0 ]; then
    echo "nothing left under $ROOT" >&2
    exit 1
fi

# Git LFS pointers instead of real files (a clone without git-lfs).
mapfile -d '' lfs < <(find "${dirs[@]}" -type f -size -1024c -print0 |
    xargs -0 -r grep -lZx -m1 'version https://git-lfs.github.com/spec/v1' || true)
for f in "${lfs[@]}"; do
    problem "/$f is a Git LFS pointer, not the real file"
done

# 4. Find the ELF files and strip them, as dh_strip would.
mapfile -d '' elfs < <(
    find "${dirs[@]}" -type f -print0 |
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

# 6. DEBIAN/ metadata. The postinst creates the system users and directories
# from sysusers.d/tmpfiles.d (cosmic-greeter), and adds what it runs to Depends.
mkdir -p DEBIAN
maint_deps=$(make-maintscripts.sh "$ROOT")
# A binary package's relation fields are one line each (the template folds
# them for reading); Description keeps its continuation lines.
sed "s#@SHLIBS@#$shlibs$maint_deps#" "$DEBDIR/control" |
    awk '/^[^ \t]/ { if (NR > 1) print buf; buf = $0
                     rel = $1 ~ /^(Pre-Depends|Depends|Recommends|Suggests|Conflicts|Breaks|Replaces|Provides):$/; next }
         rel { sub(/^[ \t]+/, " "); buf = buf $0; next }
         { print buf; buf = $0 }
         END { print buf }' > DEBIAN/control
if grep -q '@[A-Z]*@' DEBIAN/control; then
    echo "unreplaced placeholder in control:" >&2
    grep '@[A-Z]*@' DEBIAN/control >&2
    exit 1
fi
size=$(du -sk --apparent-size "${dirs[@]}" | awk '{s += $1} END {print s}')
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

find "${dirs[@]}" -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums
chmod 0755 DEBIAN
find DEBIAN -type f ! -name postinst ! -name postrm -exec chmod 0644 {} +

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
