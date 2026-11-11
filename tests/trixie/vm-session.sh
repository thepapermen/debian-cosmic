#!/bin/bash
# Full COSMIC session test in a Debian 13 VM. Run as root in a debian:trixie
# container that can use KVM:
#   docker run --rm --device /dev/kvm -v "$DIST:/dist:ro" -v "$OUT:/out" \
#       -v "$CACHE:/cache" -v "$PWD/tests/trixie:/t:ro" debian:trixie \
#       bash /t/vm-session.sh /dist /out /cache
#
# Boot 1: the official trixie cloud image installs the .deb from $1 and greetd
# (cloud-init), makes the package's cosmic-greeter.service the display manager
# as its description says, and powers off.
# Boot 2, the test: an ordinary boot to the COSMIC login screen; the password is
# typed on the VM's virtual keyboard; the session must reach the desktop. Then
# Super+T should open a terminal. Screenshots are of the VM's own screen
# (virtio-gpu, software rendering), and SSH is used only to look at processes
# and the journal. Everything goes to $2; $3 caches the cloud image.
set -u
export DEBIAN_FRONTEND=noninteractive

DIST=$1
OUT=$2
CACHE=${3:-/tmp/cache}
MEM=${VM_MEM:-3072}
CPUS=${VM_CPUS:-4}
mkdir -p "$OUT" "$CACHE"
REPORT="$OUT/vm-session.txt"
: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }
fails=0
fail() { say "FAIL: $*"; fails=$((fails + 1)); }
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
    lock_passwd: false
    plain_text_passwd: $PASS
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - $(cat "$W/key.pub")
ssh_pwauth: false
package_update: true
packages:
  - greetd
runcmd:
  - [sh, -c, "curl -fsS -o /root/$DEB http://10.0.2.2:8000/pkg/$DEB && apt-get install -y /root/$DEB > /var/log/vmtest-install.log 2>&1; echo \$? > /var/log/vmtest-install.rc"]
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
ctl() { python3 /t/vmctl.py "$QMP" "$@"; }
SSH=(ssh -i "$W/key" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=5 -o LogLevel=ERROR tester@127.0.0.1)
# Run a command in the guest; arguments are quoted for the remote shell.
g() { "${SSH[@]}" "$(printf '%q ' "$@")"; }
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
        sleep 3
    done
    say "  $what after $(( $(date +%s) - start ))s"
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

say "== login screen [$(elapsed)]"
if wait_for 180 "cosmic-greeter running" pgrep -u cosmic-greeter -x cosmic-greeter; then
    sleep 15
    ctl screendump "$OUT/1-greeter.png"
else
    fail "login screen did not start"
    ctl screendump "$OUT/1-greeter.png"
    g systemctl status display-manager.service --no-pager 2>&1 | head -n 5 | tee -a "$REPORT"
    g sudo journalctl -b -u cosmic-greeter.service -u greetd.service --no-pager | tail -n 30 | tee -a "$REPORT"
fi

say "== log in as tester (typed on the virtual keyboard) [$(elapsed)]"
ctl type "$PASS"
ctl key ret
if wait_for 180 "cosmic-session running" pgrep -u tester -x cosmic-session; then
    wait_for 120 "cosmic-panel running" pgrep -u tester -x cosmic-panel
    sleep 20
else
    fail "session did not start after login"
fi
ctl screendump "$OUT/2-desktop.png"

say "-- session processes"
for p in cosmic-comp cosmic-session cosmic-panel cosmic-bg cosmic-settings-daemon \
         cosmic-notifications cosmic-osd cosmic-idle cosmic-app-list \
         xdg-desktop-portal-cosmic cosmic-initial-setup; do
    if g pgrep -u tester -f "^(/usr/[a-z]+/)?$p( |\$)" > /dev/null; then
        say "  running  $p"
    else
        case "$p" in
            cosmic-comp|cosmic-session|cosmic-panel|cosmic-bg) fail "$p not running" ;;
            *) say "  missing  $p" ;;
        esac
    fi
done
if g systemctl is-active --quiet cosmic-greeter-daemon.service; then
    say "  running  cosmic-greeter-daemon (system service)"
else
    fail "cosmic-greeter-daemon not running"
fi
say "-- polkit authentication agent"
agents=$(g sudo journalctl -b --no-pager -g "Registered Authentication Agent" -o cat | grep -o '\[[^]]*\]' | sort -u)
say "  ${agents:-none registered}"
case "$agents" in
    *cosmic-osd*) ;;
    *) fail "the polkit agent is not cosmic-osd" ;;
esac
say "-- logind session"
g loginctl list-sessions --no-legend | tee -a "$REPORT"

say "== Super+T opens a terminal (informational) [$(elapsed)]"
ctl key meta_l-t
if wait_for 30 "cosmic-term running" pgrep -u tester -x cosmic-term; then
    sleep 5
fi
ctl screendump "$OUT/3-terminal.png"

say "== journal [$(elapsed)]"
g sudo journalctl -b --no-pager > "$OUT/journal.txt" 2>&1
g sudo journalctl -b -p err --no-pager > "$OUT/journal-errors.txt" 2>&1
g ps -eo user,pid,rss,etime,args --sort=user > "$OUT/processes.txt" 2>&1
crashes=$(grep -E -c 'dumped core|segfault at|panicked at|SIGABRT|SIGSEGV' "$OUT/journal.txt")
say "  $(wc -l < "$OUT/journal-errors.txt") error lines, $crashes crash lines (see journal.txt)"
grep -E 'dumped core|segfault at|panicked at|SIGABRT|SIGSEGV' "$OUT/journal.txt" | head -n 10 | sed 's/^/    | /' | tee -a "$REPORT"
[ "$crashes" -eq 0 ] || fail "crashes in the journal"

if [ "${VM_KEEP:-0}" = 1 ]; then
    say "== VM left running (VM_KEEP=1), pid $qpid"
else
    g sudo systemctl poweroff > /dev/null 2>&1
    timeout 60 tail --pid=$qpid -f /dev/null || kill $qpid
fi
say "== result: $fails failure(s) [$(elapsed)]"
chmod -R a+rX "$OUT"
[ "$fails" -eq 0 ]
