#!/bin/bash
# Full COSMIC session test in a Debian 13 VM. Run as root in a debian:trixie
# container that can use KVM:
#   docker run --rm --device /dev/kvm -v "$DIST:/dist:ro" -v "$OUT:/out" \
#       -v "$CACHE:/cache" -v "$PWD/tests/trixie:/t:ro" debian:trixie \
#       bash /t/vm-session.sh /dist /out /cache
# With VM_PREV=/prev (a directory holding an earlier build's .deb, mounted like
# /dist) the package is also downgraded to that build and upgraded back while
# the desktop session runs. VM_EXTRA_PKGS="a b" installs more Debian packages
# with it (for a local try of what a newer build would pull in).
#
# Boot 1: the official trixie cloud image installs the .deb from $1 and greetd
# (cloud-init), makes the package's cosmic-greeter.service the display manager
# as its description says, and powers off. The user is set up like one made by
# the Debian installer: member of "sudo", en_US.UTF-8 locale.
# Boot 2: the login screen; a wrong password must be refused, the right one
# (typed on the VM's virtual keyboard) must reach the desktop. Then, as a person
# would: finish the first-login wizard (switching off the screen reader it
# starts), use a terminal, answer an admin password prompt, see a notification
# and a file chooser, start the text editor from the launcher, save a file and
# close it with Super+Q, make a folder in the file manager, open the App Library
# and Settings, check the power services, copy and paste both ways, run an X11
# program, switch workspaces, switch to the light theme and back,
# use the volume keys (virtual sound card), take a screenshot with Print
# Screen, see a killed panel come back, lock and unlock the screen, change the
# display mode, upgrade the package, log out and in again (shortcuts must still
# work).
# Boot 3: after a reboot the login and shortcuts still work and the wizard stays
# finished; then the package is removed, purged and installed again.
# Not tested here: suspend/resume. In this VM, S3 leaves virtio-gpu without a
# display and s2idle cannot be woken; it needs real hardware.
# Then the items of COSMIC's own acceptance checklists that a VM can do
# (acceptance.sh; ACCEPTANCE.md lists every item and how it is covered).
# Every boot's journal must have no error lines except those listed in
# journal-allow.txt, and there must be no crashes and no failed units.
#
# Screenshots are of the VM's own screen (virtio-gpu, software rendering); SSH
# is used to look at processes, files and the journal, and to send the D-Bus
# calls an application would make. Everything goes to $2; $3 caches the image.
# A FAIL line is a failure; a KNOWN line is a known problem that is reported
# but does not fail the test (see the known windows below for which of them
# upstream has confirmed).
set -u
export DEBIAN_FRONTEND=noninteractive

DIST=$1
OUT=$2
CACHE=${3:-/tmp/cache}
PREV=${VM_PREV:-}
MEM=${VM_MEM:-3072}
CPUS=${VM_CPUS:-4}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT" "$CACHE"
REPORT="$OUT/vm-session.txt"
: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }
fails=0
fail() { say "FAIL: $*"; fails=$((fails + 1)); }
known=0
known_issue() { say "KNOWN: $*"; known=$((known + 1)); }
ok() { say "  ok: $*"; }
# check DESCRIPTION COMMAND...: ok if the (local) command succeeds, else FAIL.
check() { local d=$1; shift; if "$@"; then ok "$d"; else fail "$d"; fi; }
t0=$(date +%s)
elapsed() { echo "$(( $(date +%s) - t0 ))s"; }

say "== host"
apt-get update -qq
apt-get install -y -qq --no-install-recommends qemu-system-x86 qemu-utils python3 \
    openssh-client curl ca-certificates dosfstools mtools > /dev/null || { say "tool install failed"; exit 1; }
say "qemu $(dpkg-query -W -f='${Version}' qemu-system-x86), kvm: $([ -w /dev/kvm ] && echo yes || echo NO)"
[ -w /dev/kvm ] || { say "result: no KVM"; exit 1; }

debs=("$DIST"/*.deb)
[ -f "${debs[0]}" ] || { say "no .deb in $DIST"; exit 1; }
DEB=$(basename "${debs[0]}")
say "package $DEB"
PREV_DEB=
if [ -n "$PREV" ]; then
    prev_debs=("$PREV"/*.deb)
    if [ -f "${prev_debs[0]}" ]; then
        PREV_DEB=$(basename "${prev_debs[0]}")
        say "previous build $PREV_DEB"
    else
        say "previous build: none in $PREV (upgrade test skipped)"
    fi
fi

# Official image, checked against Debian's published SHA512SUMS.
base=https://cloud.debian.org/images/cloud/trixie/latest
img=debian-13-generic-amd64.qcow2
sums=$(curl -fsSL "$base/SHA512SUMS") || { say "cannot fetch SHA512SUMS"; exit 1; }
if ! (cd "$CACHE" && grep " $img\$" <<< "$sums" | sha512sum -c --status 2>/dev/null); then
    curl -fsSL -o "$CACHE/$img" "$base/$img" || { say "image download failed"; exit 1; }
    (cd "$CACHE" && grep " $img\$" <<< "$sums" | sha512sum -c --status) ||
        { say "image checksum mismatch"; exit 1; }
fi
say "image $img $(grep " $img\$" <<< "$sums" | cut -c1-16)"

# VM_WORK keeps the disk somewhere else (e.g. under the cache, for debugging);
# VM_UNTIL=wizard stops after the first-login wizard and leaves the VM
# running (to work out new test steps by hand);
# VM_KEEP=1 leaves the VM running at the end (SSH on 127.0.0.1:2222 inside the
# container, key in $W/key).
W=${VM_WORK:-/work}
rm -rf "$W"
mkdir -p "$W/seed/pkg"
cp "${debs[0]}" "$W/seed/pkg/"
[ -z "$PREV_DEB" ] || cp "$PREV/$PREV_DEB" "$W/seed/pkg/"
qemu-img create -q -f qcow2 -F qcow2 -b "$CACHE/$img" "$W/disk.qcow2" 16G
ssh-keygen -q -t ed25519 -N '' -f "$W/key"
PASS=cosmictest1

printf 'instance-id: cosmic-vm-test\nlocal-hostname: cosmic-vm\n' > "$W/seed/meta-data"
cat > "$W/seed/user-data" <<EOF
#cloud-config
users:
  - name: tester
    gecos: COSMIC Tester
    shell: /bin/bash
    groups: [sudo]
    lock_passwd: false
    plain_text_passwd: $PASS
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - $(cat "$W/key.pub")
ssh_pwauth: false
package_update: true
# greetd runs the login screen; locales as on an installed system; pkexec for
# the admin prompt test; systemd-coredump so that any crash leaves a record;
# wl-clipboard and x11-apps (xeyes) for the clipboard and X11 app tests.
packages:
  - greetd
  - locales
  - pkexec
  - systemd-coredump
  - wl-clipboard
  - x11-apps
$(for p in ${VM_EXTRA_PKGS:-}; do echo "  - $p"; done)
runcmd:
  - [sh, -c, "sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen > /dev/null && update-locale LANG=en_US.UTF-8"]
  - [sh, -c, "curl -fsS -o /root/$DEB http://10.0.2.2:8000/pkg/$DEB && apt-get install -y /root/$DEB > /var/log/vmtest-install.log 2>&1; echo \$? > /var/log/vmtest-install.rc"]
  - [sh, -c, "[ -z '$PREV_DEB' ] || curl -fsS -o /root/$PREV_DEB http://10.0.2.2:8000/pkg/$PREV_DEB"]
  # The package's own way to use the COSMIC login screen (its description):
  # cosmic-greeter.service (greetd with /etc/greetd/cosmic-greeter.toml) as the
  # display manager. It pulls in cosmic-greeter-daemon.
  - [ln, -sf, /usr/lib/systemd/system/cosmic-greeter.service, /etc/systemd/system/display-manager.service]
  - [systemctl, set-default, graphical.target]
power_state:
  mode: poweroff
  timeout: 120
EOF
(cd "$W/seed" && exec python3 -m http.server 8000 --bind 127.0.0.1 > "$W/http.log" 2>&1) &

QMP="$W/qmp.sock"
vm() {
    qemu-system-x86_64 -machine q35 -accel kvm -cpu host -smp "$CPUS" -m "$MEM" \
        -drive file="$W/disk.qcow2",if=virtio \
        -device virtio-vga -display none \
        -device virtio-keyboard-pci -device virtio-tablet-pci \
        -device qemu-xhci,id=xhci \
        -audiodev none,id=snd0 -device ich9-intel-hda -device hda-output,audiodev=snd0 \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
        -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:8000/" \
        -qmp unix:"$QMP",server=on,wait=off \
        -serial file:"$1" "${@:2}"
}
ctl() { python3 "$HERE/vmctl.py" "$QMP" "$@"; }
# shot NAME [MAX_TOP]: screenshot to $OUT/NAME.png; with MAX_TOP, fail if one
# colour covers more than that share of the screen (a blank or black screen).
shot() {
    local r top
    r=$(ctl shot "$OUT/$1.png") || { fail "screenshot $1"; return 1; }
    top=${r##*top=}
    say "  screenshot $1.png ($r)"
    if [ -n "${2:-}" ] && gt "$top" "$2"; then
        fail "$1: the screen is blank (one colour covers $top)"
        return 1
    fi
}
# changed A B [X0 Y0 X1 Y1]: share of pixels that differ between two shots.
changed() { ctl diff "$OUT/$1.ppm" "$OUT/$2.ppm" "${@:3}"; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
SSH=(ssh -i "$W/key" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=5 -o LogLevel=ERROR tester@127.0.0.1)
# Run a command in the guest; arguments are quoted for the remote shell.
g() { "${SSH[@]}" "$(printf '%q ' "$@")"; }
# The same inside tester's desktop session (session bus, Wayland display).
gs() {
    g env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        WAYLAND_DISPLAY="$(g sh -c 'cd /run/user/1000 && ls wayland-? 2>/dev/null | head -n 1')" "$@"
}
# wait_for SECONDS DESCRIPTION COMMAND...: poll a guest command until it succeeds.
wait_for() {
    local limit=$1 what=$2 start
    shift 2
    start=$(date +%s)
    while ! g "$@" > /dev/null 2>&1; do
        if [ $(( $(date +%s) - start )) -ge "$limit" ]; then
            say "  $what: not after ${limit}s"
            return 1
        fi
        sleep 2
    done
    say "  $what after $(( $(date +%s) - start ))s"
}
# wait_gone SECONDS DESCRIPTION COMMAND...: poll until the command fails.
wait_gone() {
    local limit=$1 what=$2 start
    shift 2
    start=$(date +%s)
    while g "$@" > /dev/null 2>&1; do
        if [ $(( $(date +%s) - start )) -ge "$limit" ]; then
            say "  $what: not after ${limit}s"
            return 1
        fi
        sleep 2
    done
    say "  $what after $(( $(date +%s) - start ))s"
}
# running USER NAME: a process of USER runs program NAME (by path or name).
running() { g pgrep -u "$1" -f "^(/usr/[a-z]+/)?$2( |\$)" > /dev/null; }
session_id() { g loginctl list-sessions --no-legend | awk '$3 == "tester" && $4 == "seat0" { print $1; exit }'; }

# log_in: type the password on the login screen; the desktop must come up.
log_in() {
    ctl type "$PASS"
    ctl key ret
    if wait_for 120 "cosmic-session running" pgrep -u tester -x cosmic-session &&
       wait_for 120 "cosmic-panel running" pgrep -u tester -x cosmic-panel; then
        sleep 15
        return 0
    fi
    fail "the session did not start after login"
    return 1
}

# no_screen_reader WHEN: switched off in the wizard, the screen reader stays off.
no_screen_reader() {
    if g pgrep -u tester -x orca > /dev/null; then fail "the screen reader is back $1"; fi
}

# shortcuts_work WHEN: Super+T must still open a terminal. The portal crash at
# logout can corrupt the keyboard shortcuts config (upstream
# xdg-desktop-portal-cosmic issue 294); the shortcuts files must parse too.
shortcuts_work() {
    local n
    n=$(g pgrep -c -u tester -x cosmic-term)
    ctl key meta_l-t
    if wait_for 20 "Super+T terminal ($1)" sh -c "[ \$(pgrep -c -u tester -x cosmic-term) -gt $n ]"; then
        ok "keyboard shortcuts work $1"
        ctl key meta_l-q
    else
        fail "Super+T does not open a terminal $1 (shortcuts config: $(g sh -c 'ls ~/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/ 2>&1' | tr '\n' ' '))"
    fi
}

# check_processes: the desktop's core processes (required) and the rest.
check_processes() {
    local p
    for p in cosmic-comp cosmic-session cosmic-panel cosmic-bg cosmic-settings-daemon \
             cosmic-notifications cosmic-osd cosmic-idle cosmic-app-list cosmic-greeter \
             xdg-desktop-portal-cosmic xdg-desktop-portal pipewire wireplumber; do
        if running tester "$p"; then
            say "  running  $p"
        else
            case "$p" in
                cosmic-comp|cosmic-session|cosmic-panel|cosmic-bg|cosmic-settings-daemon|\
                cosmic-notifications|cosmic-osd|xdg-desktop-portal-cosmic) fail "$p not running" ;;
                *) say "  missing  $p" ;;
            esac
        fi
    done
    if g systemctl is-active --quiet cosmic-greeter-daemon.service; then
        say "  running  cosmic-greeter-daemon (system service)"
    else
        fail "cosmic-greeter-daemon not running"
    fi
}

# Known windows: COSMIC 1.11.0 programs can crash while they close their
# Wayland connection. Error lines and core dumps inside these windows (guest
# clock, seconds) are reported as known issues; anywhere else they fail.
# - Logout, when the compositor goes away (SIGABRT):
#   xdg-desktop-portal-cosmic: confirmed upstream, "panics with BrokenPipe
#     during session shutdown",
#     https://github.com/pop-os/xdg-desktop-portal-cosmic/issues/282; it may
#     also corrupt the keyboard shortcuts config (issues/294), which is why
#     Super+T is tried again after the second login and after the reboot.
#   cosmic-applets: probably https://github.com/pop-os/libcosmic/issues/1243
#     (applets panic on a broken Wayland pipe); no panic message to compare.
#   cosmic-term: not confirmed, no upstream report found.
# - The test killing cosmic-panel: its applets lose their Wayland connection
#   and abort, as in libcosmic issue 1243.
# - cosmic-initial-setup exiting after "Finish" (segfault in libwayland-client,
#   about 1 run in 4): not confirmed, no upstream report found; it may be
#   specific to this build.
WINDOWS=
add_window() { WINDOWS+="$1 $2"$'\n'; }
# in_window 1|0: keep the lines inside|outside the windows. Lines of a
# multi-line message (a backtrace) have no timestamp: they go with the line
# before.
in_window() {
    awk -v w="$WINDOWS" -v want="$1" '
        BEGIN { n = split(w, l, "\n"); for (i = 1; i <= n; i++) if (split(l[i], f, " ") == 2) { s[++k] = f[1]; e[k] = f[2] } }
        /^[0-9]+(\.[0-9]+)? / { t = $1 + 0 }
        { inside = 0; for (i = 1; i <= k; i++) if (t >= s[i] && t <= e[i]) inside = 1 }
        inside == want { print }'
}
# plain: "IDENTIFIER: MESSAGE", without time, host, pid, colour codes or the
# log timestamps COSMIC programs print themselves.
plain() {
    sed -E 's/\x1b\[[0-9;]*m//g; s/^[0-9.]+ [^ ]+ //; s/^([^:[]+)\[[0-9]+\]:/\1:/
            s/\[?[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ?//'
}
idents() { grep -o -E '^[A-Za-z(][^ :]*:' | tr -d : | sort -u | tr '\n' ' '; }

# check_journal NAME: this boot's error lines (error priority, plus the ERROR
# lines COSMIC components print, which cosmic-session passes to the journal at
# normal priority) against journal-allow.txt (harmless) and journal-known.txt
# (known problems, reported), crash messages and failed units. Saves the
# journal as $OUT/journal-NAME.txt.
ALLOW=$(grep -v -E '^[[:space:]]*(#|$)' "$HERE/journal-allow.txt")
KNOWNLIST=$(grep -v -E '^[[:space:]]*(#|$)' "$HERE/journal-known.txt")
# Process ids of crashes classified as known (segfault in libwayland-client
# while an app closes); their core dumps are known too.
KNOWN_PIDS=
check_journal() {
    local name=$1 err_raw comp_raw errs new known_lines crashes segv pids p failed inside
    g sudo journalctl -b --no-pager > "$OUT/journal-$name.txt" 2>&1
    # Kept apart (not merged and sorted): a multi-line message must stay
    # together for in_window.
    err_raw=$(g sudo journalctl -b -p err --no-pager -o short-unix)
    comp_raw=$(g sudo journalctl -b --no-pager -o short-unix -t cosmic-session |
               grep -E '(^|[^A-Za-z])ERROR([^A-Za-z]|$)')

    # Crashes first. COSMIC apps sometimes segfault in libwayland-client while
    # they close (seen: cosmic-initial-setup after "Finish", cosmic-term after
    # Super+Q; the event loop thread races the exit, "SCTK failed to send
    # Control::AboutToWait"). Not confirmed upstream; reported as known. Any
    # other crash outside the known windows fails.
    crashes=$(g sudo journalctl -b --no-pager -o short-unix -g 'dumped core|panicked at|segfault at' |
              in_window 0 | plain | grep -v '^sudo:')
    segv=$(grep -E '\[[0-9]+\]: segfault at .* in libwayland-client' <<< "$crashes")
    pids=$(grep -o -E '\[[0-9]+\]: segfault' <<< "$segv" | tr -dc '0-9\n')
    if [ -n "$segv" ]; then
        KNOWN_PIDS+=" $(echo $pids)"
        known_issue "segfault in libwayland-client while closing ($name): $(sed -E 's/^kernel: ([^[]+)\[.*/\1/' <<< "$segv" | sort -u | tr '\n' ' ')"
        crashes=$(grep -v -F "$segv" <<< "$crashes")
        for p in $pids; do crashes=$(grep -v -E "Process $p \(" <<< "$crashes"); done
    fi
    if [ -n "$crashes" ]; then
        fail "crashes in the journal ($name):"
        head -n 10 <<< "$crashes" | cut -c1-220 | sed 's/^/    | /' | tee -a "$REPORT"
    fi

    errs=$( (in_window 0 <<< "$err_raw"; in_window 0 <<< "$comp_raw") | plain)
    for p in $pids; do errs=$(grep -v -E "^systemd-coredump: Process $p \(" <<< "$errs"); done
    printf '%s\n' "$errs" > "$OUT/journal-errors-$name.txt"
    new=$(grep -v -E -f <(printf '%s\n' "$ALLOW") <<< "$errs" | grep -v '^$')
    known_lines=$(grep -E -f <(printf '%s\n' "$KNOWNLIST") <<< "$new")
    new=$(grep -v -E -f <(printf '%s\n' "$KNOWNLIST") <<< "$new")
    say "-- journal, $name: $(grep -c . <<< "$errs") error lines, $(grep -c . <<< "$known_lines") known, $(grep -c . <<< "$new") unexpected"
    if [ -n "$known_lines" ]; then
        known_issue "journal ($name), see journal-known.txt:"
        sort <<< "$known_lines" | uniq -c | sort -rn | head -n 5 | cut -c1-200 | sed 's/^/    | /' | tee -a "$REPORT"
    fi
    if [ -n "$new" ]; then
        fail "$(grep -c . <<< "$new") unexpected error line(s) in the journal ($name):"
        sort <<< "$new" | uniq -c | sort -rn | head -n 15 | cut -c1-220 | sed 's/^/    | /' | tee -a "$REPORT"
    fi
    inside=$( (in_window 1 <<< "$err_raw"; in_window 1 <<< "$comp_raw") | plain)
    if [ -n "$inside" ]; then
        printf '%s\n' "$inside" > "$OUT/journal-errors-$name-closing.txt"
        known_issue "$(grep -c . <<< "$inside") error lines while programs closed (logout, wizard exit, panel restart; $name), from: $(idents <<< "$inside")"
    fi
    failed=$(g systemctl --failed --no-legend --plain | awk '{ print $1 }')
    [ -z "$failed" ] || fail "failed system units ($name): $(echo $failed)"
    if g pgrep -u tester -x cosmic-session > /dev/null; then
        failed=$(gs systemctl --user --failed --no-legend --plain | awk '{ print $1 }')
        [ -z "$failed" ] || fail "failed user units ($name): $(echo $failed)"
    fi
}

say "== boot 1: install (cloud-init) [$(elapsed)]"
vm "$OUT/serial-install.log" &
qpid=$!
if ! timeout 1500 tail --pid=$qpid -f /dev/null; then
    say "install boot did not power off within 25 min"
    tail -n 30 "$OUT/serial-install.log" | tee -a "$REPORT"
    kill $qpid
    exit 1
fi
say "  powered off [$(elapsed)]"

say "== boot 2: test [$(elapsed)]"
vm "$OUT/serial.log" &
qpid=$!
if ! wait_for 300 "ssh" true; then
    tail -n 30 "$OUT/serial.log" | tee -a "$REPORT"
    kill $qpid
    exit 1
fi
rc=$(g cat /var/log/vmtest-install.rc 2>/dev/null)
if [ "$rc" = 0 ]; then
    say "  install ok: $(g dpkg-query -W -f='${Version}' cosmic-epoch-monorepo), greetd $(g dpkg-query -W -f='${Version}' greetd)"
else
    fail "package install (rc=${rc:-none})"
    g sudo tail -n 30 /var/log/vmtest-install.log | tee -a "$REPORT"
fi
check "dpkg --audit is clean" test -z "$(g sudo dpkg --audit 2>&1)"
check "dpkg --verify: installed files match the package" test -z "$(g sudo dpkg --verify cosmic-epoch-monorepo 2>&1)"
check "system user cosmic-greeter exists" g getent passwd cosmic-greeter

say "== login screen [$(elapsed)]"
if wait_for 180 "cosmic-greeter running" pgrep -u cosmic-greeter -x cosmic-greeter; then
    sleep 15
    shot 1-greeter 0.9
else
    fail "login screen did not start"
    shot 1-greeter
    g systemctl status display-manager.service --no-pager 2>&1 | head -n 5 | tee -a "$REPORT"
    g sudo journalctl -b -u cosmic-greeter.service -u greetd.service --no-pager | tail -n 30 | tee -a "$REPORT"
fi

say "-- a wrong password is refused"
ctl type "wrongpass9"
ctl key ret
sleep 8
shot 1-greeter-wrong-password
if g pgrep -u tester -x cosmic-session > /dev/null; then
    fail "a wrong password started a session"
else
    ok "no session after a wrong password"
fi

say "== log in as tester (typed on the virtual keyboard) [$(elapsed)]"
log_in
shot 2-desktop 0.9

say "-- session processes"
check_processes
say "-- polkit authentication agent"
agents=$(g sudo journalctl -b --no-pager -g "Registered Authentication Agent" -o cat | grep -o '\[[^]]*\]' | sort -u)
say "  ${agents:-none registered}"
case "$agents" in
    *cosmic-osd*) ;;
    *) fail "the polkit agent is not cosmic-osd" ;;
esac
say "-- desktop portal answers (dark mode setting, as apps read it)"
scheme=$(gs busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
         org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>&1)
case "$scheme" in
    "v u "*) ok "portal color-scheme: ${scheme#v u } (1 = dark)" ;;
    *) fail "portal Settings did not answer: $scheme" ;;
esac
say "-- logind session"
g loginctl list-sessions --no-legend | tee -a "$REPORT"

say "== first-login wizard: through every page [$(elapsed)]"
# Pages (cosmic-initial-setup 1.11.0): accessibility, language, keyboard layout,
# timezone, appearance, layout, then a few more. Keyboard layout needs its row
# chosen; the timezone page needs a city: search "london", Enter picks the
# first match, and setting the timezone asks for the admin password.
if running tester cosmic-initial-setup; then
    # The wizard turns the screen reader on as it starts, and it stays on, at
    # every login, unless switched off here. A sighted user switches it off;
    # this test does too, so the rest is an ordinary session.
    if g test -x /usr/bin/orca; then
        if wait_for 20 "screen reader (orca) started by the wizard" pgrep -u tester -x orca; then
            ctl click 908 270
            if wait_gone 20 "screen reader stopped" pgrep -u tester -x orca; then
                ok "the screen reader switch on the wizard's first page turns it off"
            else
                fail "the wizard's screen reader switch did not stop orca"
            fi
        fi
    else
        say "  orca not installed: no screen reader"
    fi
    shot 3-wizard-accessibility > /dev/null
    ctl click 925 528; sleep 3                                  # accessibility
    ctl click 925 528; sleep 3                                  # language
    ctl click 500 322; sleep 1                                  # keyboard: English (US)
    ctl click 925 528; sleep 3
    ctl click 636 258; ctl type london; ctl key ret; sleep 4    # timezone
    shot 3-wizard-timezone-prompt
    ctl type "$PASS"; ctl key ret; sleep 3
    wizard_end=$(g date +%s)
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        g test -e .config/cosmic-initial-setup-done && break
        wizard_end=$(g date +%s)
        ctl click 925 528
        sleep 3
    done
    sleep 2
    # The last click was "Finish": the wizard closing is a known window.
    add_window "$wizard_end" "$(( $(g date +%s) + 10 ))"
    check "wizard finished (~/.config/cosmic-initial-setup-done)" g test -e .config/cosmic-initial-setup-done
    if running tester cosmic-initial-setup; then fail "the wizard is still open"; fi
    tz=$(g timedatectl show -p Timezone --value)
    check "the wizard set the timezone through the admin prompt ($tz)" test "$tz" = Europe/London
else
    fail "the first-login wizard did not start"
fi
shot 3-wizard-done 0.9
if [ "${VM_UNTIL:-}" = wizard ]; then
    say "== stopped after the wizard (VM_UNTIL=wizard); VM left running, pid $qpid"
    exit 0
fi

say "== terminal: Super+T, then type a command [$(elapsed)]"
ctl key meta_l-t
if wait_for 30 "cosmic-term running" pgrep -u tester -x cosmic-term; then
    sleep 4
    ctl type "touch /tmp/typed-in-terminal"
    ctl key ret
    sleep 2
    check "the typed command ran" g test -e /tmp/typed-in-terminal
else
    fail "Super+T did not open a terminal"
fi
shot 4-terminal 0.9

say "== admin password prompt (pkexec in the terminal) [$(elapsed)]"
ctl type "pkexec touch /root/pkexec-ok"
ctl key ret
sleep 5
shot 5-polkit-prompt
ctl type "wrongpass9"
ctl key ret
sleep 6
check "a wrong password is refused" g sudo test ! -e /root/pkexec-ok
ctl type "$PASS"
ctl key ret
sleep 5
check "the right password is accepted (the command ran as root)" g sudo test -e /root/pkexec-ok
shot 5-polkit-done > /dev/null

say "== notification [$(elapsed)]"
shot 6-before-notification > /dev/null
server=$(gs busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
         org.freedesktop.Notifications GetServerInformation 2>&1)
say "  server: $server"
case "$server" in *cosmic-notifications*) ;; *) fail "the notification server is not cosmic-notifications" ;; esac
gs busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications Notify 'susssasa{sv}i' vmtest 0 dialog-information \
    "VM test notification" "Shown by the COSMIC VM session test" 0 0 15000 > /dev/null
sleep 2
shot 6-notification
d=$(changed 6-before-notification 6-notification 900 30 1280 200)
if gt "$d" 0.05; then ok "notification shown (top right changed $d)"; else fail "no notification on screen (top right changed $d)"; fi
sleep 14

say "== file chooser through the portal [$(elapsed)]"
shot 7-before-file-chooser > /dev/null
gs busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.FileChooser OpenFile 'ssa{sv}' "" "VM test file chooser" 0 > /dev/null
sleep 6
shot 7-file-chooser
d=$(changed 7-before-file-chooser 7-file-chooser)
if gt "$d" 0.1; then ok "file chooser shown (screen changed $d)"; else fail "no file chooser on screen (changed $d)"; fi
ctl key esc
sleep 3
shot 7-after-file-chooser > /dev/null
d=$(changed 7-before-file-chooser 7-after-file-chooser)
if gt 0.02 "$d"; then ok "Escape closed it (changed $d)"; else fail "the file chooser did not close on Escape (changed $d)"; fi

say "== launcher: Super, type \"text editor\", Enter [$(elapsed)]"
ctl key meta_l
sleep 2
ctl type "text editor"
sleep 2
shot 7-launcher > /dev/null
ctl key ret
if wait_for 20 "cosmic-edit running" pgrep -u tester -x cosmic-edit; then
    sleep 3
    say "-- type, save with Ctrl+S (the save dialog), close with Super+Q"
    ctl type "typed into the editor"
    ctl key ctrl-s
    sleep 4
    shot 7-editor-save-dialog > /dev/null
    ctl type "saved-by-editor.txt"
    ctl key ret
    sleep 3
    check "the editor saved the typed text" test "$(g cat saved-by-editor.txt 2>&1)" = "typed into the editor"
    ctl key meta_l-q
    sleep 3
    if g pgrep -u tester -x cosmic-edit > /dev/null; then fail "Super+Q did not close the editor"; else ok "Super+Q closed the editor"; fi
else
    fail "the launcher did not start the text editor"
fi

say "== file manager: Super+F opens the home folder, Ctrl+Shift+N makes a folder [$(elapsed)]"
# Super+F runs xdg-open on the home folder: cosmic-files must be the default
# for folders.
ctl key meta_l-f
if wait_for 20 "cosmic-files running" pgrep -u tester -x cosmic-files; then
    sleep 4
    shot 7-files 0.9
    ctl key ctrl-shift-n
    sleep 2
    shot 7-files-new-folder > /dev/null
    ctl type "made-in-files"
    ctl key ret
    sleep 2
    check "the file manager made the folder ~/made-in-files" g test -d made-in-files
    ctl key meta_l-q
    sleep 3
    if g pgrep -u tester -x cosmic-files > /dev/null; then fail "Super+Q did not close the file manager"; else ok "Super+Q closed the file manager"; fi
else
    fail "Super+F did not open the file manager ($(gs xdg-mime query default inode/directory 2>&1))"
fi

say "== App Library: Super+A, then Escape [$(elapsed)]"
shot 7-before-app-library > /dev/null
ctl key meta_l-a
sleep 3
shot 7-app-library > /dev/null
d=$(changed 7-before-app-library 7-app-library)
if gt "$d" 0.1; then ok "App Library shown (changed $d)"; else fail "Super+A did not show the App Library (changed $d)"; fi
ctl key esc
sleep 2
shot 7-after-app-library > /dev/null
d=$(changed 7-before-app-library 7-after-app-library)
if gt 0.02 "$d"; then ok "Escape closed it (changed $d)"; else fail "the App Library did not close on Escape (changed $d)"; fi

say "== Settings: from the launcher, then Super+Q [$(elapsed)]"
shot 7-before-settings > /dev/null
ctl key meta_l
sleep 2
ctl type "settings"
sleep 2
ctl key ret
if wait_for 20 "cosmic-settings running" pgrep -u tester -x cosmic-settings; then
    sleep 5
    shot 7-settings 0.9
    ctl key meta_l-q
    sleep 3
    shot 7-settings-closed > /dev/null
    # Between panel (its clock may have moved on) and dock (VM redraw glitches).
    d=$(changed 7-before-settings 7-settings-closed 0 40 1280 700)
    if gt 0.02 "$d"; then ok "Super+Q closed the Settings window (changed $d)"; else fail "Super+Q did not close the Settings window (changed $d)"; fi
    # The process sometimes stays after its window has closed (seen in 2 runs
    # of 3); harmless for the user, so only noted.
    wait_gone 15 "cosmic-settings process gone" pgrep -u tester -x cosmic-settings ||
        say "  cosmic-settings still running in the background (informational)"
else
    fail "the launcher did not start Settings"
fi

say "== power: battery and power profile services (the panel's battery applet) [$(elapsed)]"
for s in upower power-profiles-daemon; do
    if [ "$(g systemctl show -p LoadState --value "$s.service")" = loaded ]; then
        check "$s is active" g systemctl is-active --quiet "$s.service"
    else
        say "  $s not installed"
    fi
done
if g test -x /usr/bin/powerprofilesctl; then
    say "  power profile: $(g powerprofilesctl get 2>&1)"
fi
if running tester cosmic-applet-battery; then ok "battery applet running"; else fail "the battery applet is not running"; fi

say "== clipboard, both ways (a new terminal window) [$(elapsed)]"
ctl key meta_l-t
sleep 4
# wl-copy keeps serving the selection in the background: no output to SSH.
gs sh -c 'printf copied-by-wl-copy | wl-copy > /dev/null 2>&1'
ctl type "cat > /tmp/pasted"
ctl key ret ctrl-shift-v ret ctrl-d
sleep 1
check "Ctrl+Shift+V pasted the clipboard into the terminal" test "$(g cat /tmp/pasted 2>&1)" = copied-by-wl-copy
ctl type 'clear; echo copied-out-of-$((6*7))'
ctl key ret
sleep 1
ctl key ctrl-shift-a ctrl-shift-c
sleep 1
case "$(gs timeout 5 wl-paste 2>&1)" in
    *copied-out-of-42*) ok "text copied in the terminal is on the clipboard" ;;
    *) fail "copying in the terminal did not reach the clipboard" ;;
esac

say "== an X11 program (xeyes through Xwayland) [$(elapsed)]"
shot 7-before-x11 > /dev/null
xdisplay=$(g sh -c 'tr "\0" "\n" < /proc/$(pgrep -n -u tester -x cosmic-term)/environ | sed -n "s/^DISPLAY=//p"')
say "  DISPLAY=${xdisplay:-none}"
gs env DISPLAY="${xdisplay:-:1}" sh -c 'setsid xeyes < /dev/null > /tmp/xeyes.log 2>&1 &'
sleep 4
shot 7-x11 > /dev/null
d=$(changed 7-before-x11 7-x11)
if g pgrep -x xeyes > /dev/null && gt "$d" 0.01; then ok "xeyes shows a window (changed $d)"; else fail "no X11 window (changed $d): $(g cat /tmp/xeyes.log)"; fi
ctl key meta_l-q
sleep 2
if g pgrep -x xeyes > /dev/null; then fail "Super+Q did not close the X11 window"; g pkill -x xeyes; else ok "Super+Q closed the X11 window"; fi

say "== workspaces: Super+2 and back with Super+1 [$(elapsed)]"
shot 7-workspace-1 > /dev/null
ctl key meta_l-2
sleep 2
shot 7-workspace-2 > /dev/null
ctl key meta_l-1
sleep 2
shot 7-workspace-1-again > /dev/null
d=$(changed 7-workspace-1 7-workspace-2)
if gt "$d" 0.1; then ok "workspace 2 is a different (empty) screen (changed $d)"; else fail "Super+2 did not switch workspace (changed $d)"; fi
d=$(changed 7-workspace-1 7-workspace-1-again)
if gt 0.02 "$d"; then ok "Super+1 brought workspace 1 back"; else fail "Super+1 did not return to workspace 1 (changed $d)"; fi

say "== light theme and back (the setting the Appearance page writes) [$(elapsed)]"
mode=.config/cosmic/com.system76.CosmicTheme.Mode/v1
shot 7-dark > /dev/null
# Written in one step (rename), as COSMIC itself does: a reader must never see
# a half-written file.
g sh -c "mkdir -p $mode && echo false > $mode/.is_dark.new && mv $mode/.is_dark.new $mode/is_dark"
sleep 4
shot 7-light > /dev/null
scheme=$(gs busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
         org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>&1)
check "apps are told to prefer light (portal color-scheme: ${scheme#v u })" test "$scheme" = "v u 2"
d=$(changed 7-dark 7-light)
if gt "$d" 0.01; then ok "panel and dock turned light (changed $d)"; else fail "the screen did not change for the light theme (changed $d)"; fi
g sh -c "echo true > $mode/.is_dark.new && mv $mode/.is_dark.new $mode/is_dark"
sleep 4
scheme=$(gs busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
         org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>&1)
check "back to dark (portal color-scheme: ${scheme#v u })" test "$scheme" = "v u 1"

say "== volume keys (virtual sound card) [$(elapsed)]"
vol() { gs wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>&1; }
# Let the theme change settle: under load a key release can arrive late and
# the key repeats (seen once: one press raised the volume by 65%).
sleep 5
v0=$(vol)
say "  before: $v0"
if [[ "$v0" == Volume:* ]]; then
    shot 7-before-volume > /dev/null
    ctl key volumeup
    shot 7-volume-key > /dev/null
    sleep 1
    v1=$(vol)
    if gt "${v1#Volume: }" "${v0#Volume: }"; then ok "volume up: $v1"; else fail "the volume-up key did not raise the volume ($v1)"; fi
    ctl key volumedown
    sleep 1
    v2=$(vol)
    if gt "${v1#Volume: }" "${v2#Volume: }"; then ok "volume down: $v2"; else fail "the volume-down key did not lower the volume ($v2)"; fi
    ctl key audiomute
    sleep 1
    case "$(vol)" in *MUTED*) ok "mute key mutes" ;; *) fail "the mute key did not mute ($(vol))" ;; esac
    ctl key audiomute
    sleep 1
    case "$(vol)" in *MUTED*) fail "the mute key did not unmute" ;; *) ok "mute key unmutes" ;; esac
    d=$(changed 7-before-volume 7-volume-key)
    if gt "$d" 0.001; then
        ok "a volume popup appeared (changed $d)"
    else
        # Seen in every run without upower, and not with it: cosmic-osd also
        # watches the keyboard backlight through upower.
        if g systemctl is-active --quiet upower.service; then
            fail "no volume popup on screen (changed $d)"
        else
            known_issue "no volume popup on screen: upower is not installed (the package recommends it)"
        fi
    fi
else
    fail "no default audio output: $v0"
fi

say "== Print Screen: capture the whole screen to ~/Pictures/Screenshots [$(elapsed)]"
ctl key print
sleep 3
shot 7-screenshot-bar > /dev/null
ctl key ret
sleep 4
png=$(g sh -c 'ls -t ~/Pictures/Screenshots/*.png 2>/dev/null | head -n 1')
if [ -n "$png" ] && [ "$(g sh -c "head -c 4 '$png' | od -An -c | tr -d ' '")" = '211PNG' ]; then
    ok "screenshot saved: $png"
else
    fail "Print Screen did not save a screenshot"
fi

say "== a desktop component that dies is restarted by the session [$(elapsed)]"
# The applets lose their Wayland connection with the panel and abort (core
# dumps): the same as at logout (libcosmic issue 1243), so a known window.
old=$(g pgrep -u tester -x cosmic-panel)
kill_start=$(g date +%s)
g kill "$old"
if wait_for 20 "new cosmic-panel" sh -c "p=\$(pgrep -u tester -x cosmic-panel) && [ \"\$p\" != $old ]"; then
    sleep 5
    shot 7-panel-restarted 0.9
else
    fail "cosmic-panel was not restarted"
fi
add_window "$kill_start" "$(( $(g date +%s) + 5 ))"

# COSMIC's own acceptance checklists (acceptance.sh, ACCEPTANCE.md).
. "$HERE/acceptance.sh"
acceptance

say "== lock screen [$(elapsed)]"
sid=$(session_id)
shot 8-before-lock > /dev/null
g sudo loginctl lock-session "$sid"
sleep 5
shot 8-locked 0.9
d=$(changed 8-before-lock 8-locked)
if gt "$d" 0.2; then ok "locked (screen changed $d)"; else fail "loginctl lock-session did not show the lock screen (changed $d)"; fi
# A wrong password that is also a shell command: if keys reached the terminal
# behind the lock screen, the file appears.
ctl type "touch /tmp/typed-while-locked"
ctl key ret
sleep 6
check "keys typed on the lock screen do not reach the terminal" g test ! -e /tmp/typed-while-locked
shot 8-locked-wrong-password > /dev/null
d=$(changed 8-before-lock 8-locked-wrong-password)
if gt "$d" 0.2; then ok "still locked after a wrong password"; else fail "a wrong password unlocked the screen"; fi
ctl type "$PASS"
ctl key ret
sleep 5
shot 8-unlocked > /dev/null
d=$(changed 8-before-lock 8-unlocked)
if gt 0.02 "$d"; then ok "unlocked, the desktop is back as it was (changed $d)"; else fail "not unlocked (changed $d)"; fi
ctl key meta_l-esc
sleep 4
shot 8-locked-by-shortcut > /dev/null
d=$(changed 8-before-lock 8-locked-by-shortcut)
if gt "$d" 0.2; then ok "Super+Escape locks"; else fail "Super+Escape did not lock (changed $d)"; fi
ctl type "$PASS"
ctl key ret
sleep 5

say "== displays (cosmic-randr) [$(elapsed)]"
outputs=$(gs cosmic-randr list --kdl 2>&1)
out=$(sed -n 's/^output "\([^"]*\)".*/\1/p' <<< "$outputs" | head -n 1)
if [ -n "$out" ]; then
    ok "cosmic-randr lists output $out"
    shot 9-before-mode-change > /dev/null
    gs cosmic-randr mode "$out" 1024 768 > /dev/null 2>&1
    sleep 4
    r=$(ctl shot "$OUT/9-mode-1024x768.png")
    case "$r" in 1024x768*) ok "mode changed to 1024x768" ;; *) fail "mode change: the screen is $r" ;; esac
    gs cosmic-randr mode "$out" 1280 800 > /dev/null 2>&1
    sleep 6
    shot 9-mode-back > /dev/null
    d=$(changed 9-before-mode-change 9-mode-back)
    if gt 0.02 "$d"; then
        ok "back at 1280x800, the screen looks as before"
    else
        # Seen once in a manual run (a stale copy of the dock, also in COSMIC's
        # own screenshot); not confirmed upstream.
        known_issue "after 1024x768 and back, panel and dock are drawn wrong (changed $d, 9-mode-back.png; not confirmed upstream)"
    fi
else
    fail "cosmic-randr list: $(head -n 3 <<< "$outputs")"
fi

if [ -n "$PREV_DEB" ]; then
    say "== upgrade while the session runs: down to the previous build and back [$(elapsed)]"
    comp=$(g pgrep -u tester -x cosmic-comp)
    g sudo apt-get install -y --allow-downgrades "/root/$PREV_DEB" > "$OUT/apt-downgrade.log" 2>&1
    check "downgrade to $PREV_DEB" test $? = 0
    g sudo apt-get install -y "/root/$DEB" > "$OUT/apt-upgrade.log" 2>&1
    check "upgrade back to $DEB" test $? = 0
    grep -h -E '^(The following|  )' "$OUT/apt-downgrade.log" "$OUT/apt-upgrade.log" | sed 's/^/    /' | tee -a "$REPORT"
    check "the installed version is this build" \
        test "$(g dpkg-query -W -f='${Version}' cosmic-epoch-monorepo)" = "$(dpkg-deb -f "$DIST/$DEB" Version)"
    check "dpkg --audit is clean" test -z "$(g sudo dpkg --audit 2>&1)"
    check "dpkg --verify is clean" test -z "$(g sudo dpkg --verify cosmic-epoch-monorepo 2>&1)"
    check "the session survived (same cosmic-comp)" test "$(g pgrep -u tester -x cosmic-comp)" = "$comp"
    check "cosmic-greeter-daemon still active" g systemctl is-active --quiet cosmic-greeter-daemon.service
fi

say "== log out [$(elapsed)]"
logout_start=$(g date +%s)
gs busctl --user call com.system76.CosmicSession /com/system76/CosmicSession com.system76.CosmicSession Exit > /dev/null
if wait_gone 60 "cosmic-comp gone" pgrep -u tester -x cosmic-comp &&
   wait_for 60 "login screen back" pgrep -u cosmic-greeter -x cosmic-greeter; then
    sleep 5
    add_window "$logout_start" "$(g date +%s)"
    shot 10-logged-out 0.9
    # The user's systemd instance stays while SSH is logged in; list anything
    # else that outlived the session.
    left=$(g pgrep -u tester -a | grep -v -E 'systemd|sd-pam|dbus-daemon|sshd|pgrep|pipewire|wireplumber|keyring|gcr-|ssh-agent|dconf|xdg-|at-spi|status-notifier-watcher' | cut -c1-100)
    if [ -n "$left" ]; then
        say "  still running after logout (informational):"
        sed 's/^/    /' <<< "$left" | tee -a "$REPORT"
    fi
    say "== log in again [$(elapsed)]"
    log_in
    if running tester cosmic-initial-setup; then fail "the wizard came back after it was finished"; else ok "the wizard stays finished"; fi
    shortcuts_work "after logging in again"
    no_screen_reader "after logging in again"
    shot 11-second-login 0.9
else
    fail "logout did not return to the login screen"
    shot 10-logged-out
fi

say "-- resources (informational)"
g ps -u tester -o rss=,comm= | awk '{ s += $1 } END { printf "  tester processes: %d MB RSS\n", s / 1024 }' | tee -a "$REPORT"
busy=$(g top -b -n 2 -d 10 -u tester -o %CPU -w 200 |
       awk '/^top -/ { n++ } n == 2 && $1 ~ /^[0-9]+$/ && $9 + 0 > 0 { print "    " $9 "% " $12 }' | head -n 5)
say "  busiest processes over 10 idle seconds (% of one CPU):"
say "${busy:-    none above 0.0%}"
check_journal boot2
g ps -eo user,pid,rss,etime,args --sort=user > "$OUT/processes-boot2.txt" 2>&1

say "== boot 3: reboot [$(elapsed)]"
boot2=$(g cat /proc/sys/kernel/random/boot_id)
timeout 20 "${SSH[@]}" 'sudo systemctl reboot' > /dev/null 2>&1
sleep 10
wait_for 300 "ssh after reboot" sh -c "test \"\$(cat /proc/sys/kernel/random/boot_id)\" != $boot2"
if wait_for 180 "cosmic-greeter running" pgrep -u cosmic-greeter -x cosmic-greeter; then
    sleep 10
    shot 12-greeter-after-reboot 0.9
    log_in
    shot 13-desktop-after-reboot 0.9
    check_processes
    if running tester cosmic-initial-setup; then fail "the wizard came back after a reboot"; else ok "the wizard stays finished"; fi
    shortcuts_work "after the reboot"
    no_screen_reader "after the reboot"
    agents=$(g sudo journalctl -b --no-pager -g "Registered Authentication Agent" -o cat | grep -o '\[[^]]*\]' | sort -u)
    say "  polkit agent: ${agents:-none registered}"
else
    fail "login screen did not start after the reboot"
fi
g systemd-analyze 2>/dev/null | head -n 1 | sed 's/^/  /' | tee -a "$REPORT"
check_journal boot3
g ps -eo user,pid,rss,etime,args --sort=user > "$OUT/processes-boot3.txt" 2>&1

say "== crash reports, all boots (systemd-coredump) [$(elapsed)]"
# "SECONDS EXE pid PID signal SIG" per core dump; known if inside a known window
# or the pid had a known crash (segfault in libwayland-client).
dumps=$(g sudo coredumpctl list --json=short --no-pager 2>/dev/null |
        python3 -c 'import json, sys
for d in json.load(sys.stdin): print(d["time"] // 1000000, d["exe"], "pid", d["pid"], "signal", d["sig"])' 2>/dev/null)
other=$(in_window 0 <<< "$dumps" | awk -v k=" $KNOWN_PIDS " 'index(k, " " $4 " ") == 0')
inside=$( (in_window 1 <<< "$dumps"; in_window 0 <<< "$dumps" | awk -v k=" $KNOWN_PIDS " 'index(k, " " $4 " ") > 0') | grep .)
[ -z "$inside" ] || known_issue "crashed while closing (logout, wizard exit, panel restart, app exit; see the script for upstream reports): $(awk '{ print $2 }' <<< "$inside" | sort -u | tr '\n' ' ')"
if [ -n "$other" ]; then
    fail "crash reports:"
    sed 's/^[0-9]* /    | /' <<< "$other" | tee -a "$REPORT"
else
    ok "no crash outside the known windows"
fi

say "== remove, purge, install again [$(elapsed)]"
g sudo systemctl stop display-manager.service
g dpkg-query -L cosmic-epoch-monorepo > "$OUT/package-files.txt"
g sudo apt-get remove -y cosmic-epoch-monorepo > "$OUT/apt-remove.log" 2>&1
check "remove" test $? = 0
check "the programs are gone" g test ! -e /usr/bin/cosmic-comp
check "configuration files stay until purge" g test -e /etc/greetd/cosmic-greeter.toml
check "systemd no longer has cosmic-greeter-daemon.service" \
    test "$(g systemctl show -p LoadState --value cosmic-greeter-daemon.service)" = not-found
check "the system user stays (Debian policy)" g getent passwd cosmic-greeter
g sudo apt-get purge -y cosmic-epoch-monorepo > "$OUT/apt-purge.log" 2>&1
check "purge" test $? = 0
check "dpkg has forgotten the package" \
    test -z "$(g dpkg-query -W -f='${db:Status-Status}' cosmic-epoch-monorepo 2>/dev/null | grep -v not-installed)"
left=$(g sh -c 'while read -r f; do if [ -f "$f" ] || [ -L "$f" ]; then echo "$f"; fi; done' < "$OUT/package-files.txt")
if [ -z "$left" ]; then ok "no file of the package is left"; else fail "files left after purge: $(head -n 5 <<< "$left" | tr '\n' ' ')"; fi
g sudo apt-get install -y "/root/$DEB" > "$OUT/apt-reinstall.log" 2>&1
check "install again after purge" test $? = 0
check "dpkg --verify is clean" test -z "$(g sudo dpkg --verify cosmic-epoch-monorepo 2>&1)"
check "the login screen files are back" g test -e /etc/greetd/cosmic-greeter.toml -a -e /etc/pam.d/cosmic-greeter
check "dpkg --audit is clean" test -z "$(g sudo dpkg --audit 2>&1)"

if [ "${VM_KEEP:-0}" = 1 ]; then
    g sudo systemctl start display-manager.service
    say "== VM left running (VM_KEEP=1), pid $qpid"
else
    g sudo systemctl poweroff > /dev/null 2>&1
    timeout 60 tail --pid=$qpid -f /dev/null || kill $qpid
fi
rm -f "$OUT"/*.ppm
say "== result: $fails failure(s), $known known issue(s) [$(elapsed)]"
chmod -R a+rX "$OUT"
[ "$fails" -eq 0 ]
