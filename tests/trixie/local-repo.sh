#!/bin/sh
# A local APT repository for the COSMIC Store tests (Fedora's
# desktop_update_graphical and "package manager: install an app"). Runs as root
# in the VM: vm-session.sh pipes it over ssh ("sh -s setup" or "sh -s restore").
#
# setup:   vmtest-update 1.0 is installed and 2.0 is in the repository (an
#          update), and vmtest-app 1.0 is in the repository with AppStream data
#          (DEP-11), so the Store lists it as an app. While the test runs, APT
#          sees only this repository: no Debian update gets mixed in, and no
#          network is needed.
# restore: removes both packages and the repository, puts Debian's sources back.
set -eu
REPO=/srv/vmtest-repo
LIST=/etc/apt/sources.list.d/vmtest.list
SAVED=/root/vmtest-saved-sources

# deb NAME VERSION [FILES_DIR]: build NAME_VERSION_all.deb in $T.
deb() {
    d=$T/$1-$2
    mkdir -p "$d/DEBIAN" "$d/usr/share/doc/$1"
    [ -z "${3:-}" ] || cp -a "$3/." "$d/"
    cat > "$d/DEBIAN/control" <<EOF
Package: $1
Version: $2
Architecture: all
Maintainer: COSMIC VM test <root@localhost>
Priority: optional
Section: misc
Description: package for the COSMIC VM tests
 Made by tests/trixie/local-repo.sh; it only exists inside the test VM.
EOF
    echo "$2" > "$d/usr/share/doc/$1/version"
    dpkg-deb --root-owner-group --build "$d" "$T/${1}_${2}_all.deb" > /dev/null
}

setup() {
    T=$(mktemp -d)
    # The app: a launcher entry and a program that opens a small window.
    a=$T/app-files
    mkdir -p "$a/usr/bin" "$a/usr/share/applications" "$a/usr/share/metainfo"
    cat > "$a/usr/bin/vmtest-app" <<'EOF'
#!/bin/sh
exec zenity --info --title "VM Test App" --text "Installed from the COSMIC Store"
EOF
    chmod 755 "$a/usr/bin/vmtest-app"
    cat > "$a/usr/share/applications/org.example.VmtestApp.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=VM Test App
Comment=Package for the COSMIC VM install test
Exec=vmtest-app
Icon=accessories-calculator
Categories=Utility;
EOF
    deb vmtest-update 1.0
    deb vmtest-update 2.0
    deb vmtest-app 1.0 "$a"
    dpkg -i "$T/vmtest-update_1.0_all.deb" > /dev/null

    rm -rf "$REPO"
    pool=$REPO/pool dist=$REPO/dists/vmtest/main
    mkdir -p "$pool" "$dist/binary-amd64" "$dist/dep11"
    cp "$T/vmtest-update_2.0_all.deb" "$T/vmtest-app_1.0_all.deb" "$pool/"
    (cd "$REPO" && apt-ftparchive packages pool > "$dist/binary-amd64/Packages" 2> /dev/null)
    gzip -k "$dist/binary-amd64/Packages"
    # AppStream data as Debian's archive has it (what the Store lists).
    cat > "$dist/dep11/Components-amd64.yml" <<'EOF'
---
File: DEP-11
Version: '0.16'
Origin: vmtest-main
---
Type: desktop-application
ID: org.example.VmtestApp
Package: vmtest-app
Name:
  C: VM Test App
Summary:
  C: Package for the COSMIC VM install test
Description:
  C: <p>A small app that exists only inside the COSMIC test VM.</p>
Categories:
- Utility
Launchable:
  desktop-id:
  - org.example.VmtestApp.desktop
Icon:
  stock: accessories-calculator
EOF
    # Both, as for Packages: from a file: repository APT reads the
    # uncompressed one, and without it skips the AppStream data.
    gzip -k "$dist/dep11/Components-amd64.yml"
    (cd "$REPO/dists/vmtest" && apt-ftparchive \
        -o APT::FTPArchive::Release::Suite=vmtest \
        -o APT::FTPArchive::Release::Codename=vmtest \
        -o APT::FTPArchive::Release::Components=main \
        -o APT::FTPArchive::Release::Architectures=amd64 \
        release . > Release 2> /dev/null)

    mkdir -p "$SAVED"
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
        [ -f "$f" ] && [ "$f" != "$LIST" ] && mv "$f" "$SAVED/"
    done
    echo "deb [trusted=yes] file:$REPO vmtest main" > "$LIST"
    rm -rf "$T"
}

restore() {
    apt-get purge -y -qq vmtest-app vmtest-update > /dev/null 2>&1 || true
    rm -rf "$REPO" "$LIST"
    if [ -d "$SAVED" ]; then
        for f in "$SAVED"/*; do
            case ${f##*/} in
                sources.list) mv "$f" /etc/apt/ ;;
                *) mv "$f" /etc/apt/sources.list.d/ ;;
            esac
        done
        rmdir "$SAVED"
    fi
    apt-get update -qq > /dev/null 2>&1 || true
}

"$1"
