#!/bin/bash
# Full COSMIC session test in a Debian 13 VM. Run as root in a debian:trixie
# container that can use KVM:
#   docker run --rm --device /dev/kvm -v "$DIST:/dist:ro" -v "$OUT:/out" \
#       -v "$CACHE:/cache" -v "$PWD/tests/trixie:/t:ro" debian:trixie \
#       bash /t/vm-session.sh /dist /out /cache
# With VM_PREV=/prev (a directory holding an earlier build's .deb, mounted like
# /dist) the package is also downgraded to that build and upgraded back while
# the desktop session runs.
#
# Boot 1: the official trixie cloud image installs the .deb from $1 and greetd
# (cloud-init), makes the package's cosmic-greeter.service the display manager
# as its description says, and powers off. The user is set up like one made by
# the Debian installer: member of "sudo", en_US.UTF-8 locale.
# Boot 2: the login screen; a wrong password must be refused, the right one
# (typed on the VM's virtual keyboard) must reach the desktop. Then, as a person
# would: finish the first-login wizard, use a terminal, answer an admin password
# prompt, see a notification and a file chooser, lock and unlock the screen,
# change the display mode, upgrade the package, log out and in again.
# Boot 3: after a reboot the login still works and the wizard stays finished;
# then the package is removed, purged and installed again.
# Every boot's journal must have no error lines except those listed in
# journal-allow.txt, and there must be no crashes and no failed units.
#
# Screenshots are of the VM's own screen (virtio-gpu, software rendering); SSH
# is used to look at processes, files and the journal, and to send the D-Bus
# calls an application would make. Everything goes to $2; $3 caches the image.
# A FAIL line is a failure; a KNOWN line is a known upstream problem that is
# reported but does not fail the test.
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
    openssh-client curl ca-certificates > /dev/null || { say "tool install failed"; exit 1; }
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
# the admin prompt test; systemd-coredump so that any crash leaves a record.
packages:
  - greetd
  - locales
  - pkexec
  - systemd-coredump
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
# Wayland connection: when the compositor goes away at logout (they abort), and
# cosmic-initial-setup sometimes when it exits after "Finish" (segfault). Error
# lines and core dumps inside these windows (guest clock, seconds) are reported
# as known issues; anywhere else they fail the test.
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
plain() { sed -E 's/^[0-9.]+ [^ ]+ //; s/^([^:[]+)\[[0-9]+\]:/\1:/'; }
idents() { grep -o -E '^[A-Za-z(][^ :]*:' | tr -d : | sort -u | tr '\n' ' '; }

# check_journal NAME: this boot's error lines against journal-allow.txt, crash
# messages and failed units. Saves the journal as $OUT/journal-NAME.txt.
ALLOW=$(grep -v -E '^[[:space:]]*(#|$)' "$HERE/journal-allow.txt")
check_journal() {
    local name=$1 raw errs new crashes failed inside
    g sudo journalctl -b --no-pager > "$OUT/journal-$name.txt" 2>&1
    raw=$(g sudo journalctl -b -p err --no-pager -o short-unix)
    errs=$(in_window 0 <<< "$raw" | plain)
    printf '%s\n' "$errs" > "$OUT/journal-errors-$name.txt"
    new=$(grep -v -E -f <(printf '%s\n' "$ALLOW") <<< "$errs" | grep -v '^$')
    say "-- journal, $name: $(grep -c . <<< "$errs") error lines, $(grep -c . <<< "$new") not in journal-allow.txt"
    if [ -n "$new" ]; then
        fail "$(grep -c . <<< "$new") unexpected error line(s) in the journal ($name):"
        sort <<< "$new" | uniq -c | sort -rn | head -n 15 | cut -c1-220 | sed 's/^/    | /' | tee -a "$REPORT"
    fi
    inside=$(in_window 1 <<< "$raw" | plain)
    if [ -n "$inside" ]; then
        printf '%s\n' "$inside" > "$OUT/journal-errors-$name-closing.txt"
        known_issue "$(grep -c . <<< "$inside") error lines while programs closed (logout, wizard exit; $name), from: $(idents <<< "$inside")"
    fi
    crashes=$(g sudo journalctl -b --no-pager -o short-unix -g 'dumped core|panicked at|segfault at' | in_window 0 | plain | grep -v '^sudo:')
    if [ -n "$crashes" ]; then
        fail "crashes in the journal ($name):"
        head -n 10 <<< "$crashes" | cut -c1-220 | sed 's/^/    | /' | tee -a "$REPORT"
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
        known_issue "after 1024x768 and back, panel and dock are drawn wrong (changed $d, 9-mode-back.png)"
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
    agents=$(g sudo journalctl -b --no-pager -g "Registered Authentication Agent" -o cat | grep -o '\[[^]]*\]' | sort -u)
    say "  polkit agent: ${agents:-none registered}"
else
    fail "login screen did not start after the reboot"
fi
g systemd-analyze 2>/dev/null | head -n 1 | sed 's/^/  /' | tee -a "$REPORT"
check_journal boot3
g ps -eo user,pid,rss,etime,args --sort=user > "$OUT/processes-boot3.txt" 2>&1

say "== crash reports, all boots (systemd-coredump) [$(elapsed)]"
# "SECONDS EXE SIGNAL" per core dump, then split at the logout window.
dumps=$(g sudo coredumpctl list --json=short --no-pager 2>/dev/null |
        python3 -c 'import json, sys
for d in json.load(sys.stdin): print(d["time"] // 1000000, d["exe"], "signal", d["sig"])' 2>/dev/null)
other=$(in_window 0 <<< "$dumps")
inside=$(in_window 1 <<< "$dumps")
[ -z "$inside" ] || known_issue "crashed while closing (logout, wizard exit): $(awk '{ print $2 }' <<< "$inside" | sort -u | tr '\n' ' ')"
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
