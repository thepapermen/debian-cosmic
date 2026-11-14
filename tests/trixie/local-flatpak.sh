#!/bin/sh
# A local Flatpak repository for the COSMIC Store's Flatpak test. Runs as root
# in the VM: vm-session.sh pipes it over ssh ("sh -s setup" or "sh -s restore").
#
# setup:   builds a tiny runtime (dash and libc from the VM, as Flatpak's own
#          test suite does) and an app on it with AppStream data and an icon,
#          exports both to /srv/vmtest-flatpak, signed with a key made here
#          (thrown away with the repository), adds that as the system remote
#          "vmtest" and writes /srv/vmtest.flatpakrepo for the Store's Import.
#          No network, nothing from Flathub.
# restore: uninstalls them, removes the remotes and the repository.
set -eu
REPO=/srv/vmtest-flatpak
APP=org.example.VmtestFlat
RT=org.example.VmtestPlatform

# png FILE SIZE: a plain square icon (blue), without image tools.
png() {
    python3 - "$1" "$2" <<'EOF'
import struct, sys, zlib
name, n = sys.argv[1], int(sys.argv[2])
row = b"\0" + bytes([40, 110, 220]) * n
def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
with open(name, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * n)) + chunk(b"IEND", b""))
EOF
}

setup() {
    T=$(mktemp -d)
    rm -rf "$REPO"                  # (build-export makes the repository)
    export GNUPGHOME=$T/gnupg
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
        --quick-gen-key 'COSMIC VM test <vmtest@localhost>' default default never 2> /dev/null
    KEY=$(gpg --list-keys --with-colons 2> /dev/null | awk -F: '/^fpr/ { print $10; exit }')
    SIGN="--gpg-sign=$KEY --gpg-homedir=$GNUPGHOME"

    # The runtime: /usr/bin/sh and what it needs (a runtime's tree is usr/).
    r=$T/runtime
    mkdir -p "$r/files" "$r/usr/bin" "$r/usr/lib/x86_64-linux-gnu" "$r/usr/lib64"
    cp /bin/dash "$r/usr/bin/sh"
    cp /lib/x86_64-linux-gnu/libc.so.6 "$r/usr/lib/x86_64-linux-gnu/"
    cp /lib64/ld-linux-x86-64.so.2 "$r/usr/lib64/"
    printf '[Runtime]\nname=%s\n' "$RT" > "$r/metadata"
    flatpak build-export $SIGN --runtime --disable-sandbox --no-update-summary "$REPO" "$r" master > /dev/null

    # The app: a command that leaves a mark in its data directory.
    a=$T/app
    mkdir -p "$a/files/bin" "$a/files/share/applications" "$a/files/share/metainfo" \
        "$a/files/share/icons/hicolor/64x64/apps" "$a/files/share/app-info/xmls" \
        "$a/files/share/app-info/icons/flatpak/64x64"
    printf '[Application]\nname=%s\nruntime=%s/x86_64/master\ncommand=vmtest-flat\n' "$APP" "$RT" > "$a/metadata"
    cat > "$a/files/bin/vmtest-flat" <<'EOF'
#!/bin/sh
echo "ran in the sandbox" > "$XDG_DATA_HOME/vmtest-flat-ran"
EOF
    chmod 755 "$a/files/bin/vmtest-flat"
    cat > "$a/files/share/applications/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=VM Test Flatpak
Comment=Flatpak for the COSMIC VM install test
Exec=vmtest-flat
Icon=$APP
Categories=Utility;
EOF
    png "$a/files/share/icons/hicolor/64x64/apps/$APP.png" 64
    cp "$a/files/share/icons/hicolor/64x64/apps/$APP.png" "$a/files/share/app-info/icons/flatpak/64x64/$APP.png"
    cat > "$a/files/share/metainfo/$APP.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP</id>
  <name>VM Test Flatpak</name>
  <summary>Flatpak for the COSMIC VM install test</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <description><p>A small Flatpak that exists only inside the COSMIC test VM.</p></description>
  <launchable type="desktop-id">$APP.desktop</launchable>
  <categories><category>Utility</category></categories>
</component>
EOF
    # The AppStream catalogue entry (what flatpak build-update-repo collects).
    cat > "$T/$APP.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<components version="0.16" origin="flatpak">
  <component type="desktop-application">
    <id>$APP</id>
    <name>VM Test Flatpak</name>
    <summary>Flatpak for the COSMIC VM install test</summary>
    <description><p>A small Flatpak that exists only inside the COSMIC test VM.</p></description>
    <project_license>MIT</project_license>
    <launchable type="desktop-id">$APP.desktop</launchable>
    <categories><category>Utility</category></categories>
    <icon type="cached" width="64" height="64">$APP.png</icon>
    <bundle type="flatpak">app/$APP/x86_64/master</bundle>
  </component>
</components>
EOF
    gzip -c "$T/$APP.xml" > "$a/files/share/app-info/xmls/$APP.xml.gz"
    flatpak build-finish "$a" --command=vmtest-flat > /dev/null
    flatpak build-export $SIGN --no-update-summary "$REPO" "$a" master > /dev/null
    flatpak build-update-repo $SIGN "$REPO" > /dev/null

    gpg --export "$KEY" > "$T/key.gpg"
    flatpak remote-add --system --if-not-exists --gpg-import="$T/key.gpg" vmtest "file://$REPO"
    cat > /srv/vmtest.flatpakrepo <<EOF
[Flatpak Repo]
Title=VM Test Repository
Url=file://$REPO
GPGKey=$(base64 -w 0 "$T/key.gpg")
EOF
    chmod 644 /srv/vmtest.flatpakrepo
    flatpak update --system --appstream vmtest > /dev/null 2>&1 || true
    rm -rf "$T"
}

restore() {
    flatpak uninstall --system -y --noninteractive "$APP" > /dev/null 2>&1 || true
    flatpak uninstall --system -y --noninteractive "$RT" > /dev/null 2>&1 || true
    flatpak remote-delete --system --force vmtest > /dev/null 2>&1 || true
    rm -rf "$REPO" /srv/vmtest.flatpakrepo
}

"$1"
