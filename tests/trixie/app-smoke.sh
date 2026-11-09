#!/bin/bash
# COSMIC smoke test on Debian 13, run as root in a clean debian:trixie container:
#   docker run --rm -v "$DIST:/dist:ro" -v "$OUT:/out" -v "$PWD/tests/trixie:/t:ro" \
#       debian:trixie bash /t/app-smoke.sh /dist /out
#
# Installs the .deb from $1, starts a headless wlroots compositor (sway) with
# software rendering, and starts COSMIC programs inside it one at a time:
#   window  - an app must open a window and still be running a few seconds later
#   layer   - a shell component (panel, background...) must still be running
#   nested  - cosmic-comp itself, as a window inside sway (its winit backend)
# Each gets a screenshot and its log in $2. Only "required" entries can fail the
# run; the rest are recorded, because sway is not cosmic-comp and some COSMIC
# components need cosmic-comp's own protocols.
#
# Optional third argument and on: "name:kind:required|info" entries to test
# instead of the default list (used to check the harness with non-COSMIC apps).
set -u
export DEBIAN_FRONTEND=noninteractive

DIST=$1
OUT=$2
shift 2
mkdir -p "$OUT"
REPORT="$OUT/app-smoke.txt"
: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }

if [ "$#" -gt 0 ]; then
    specs=("$@")
else
    specs=(
        cosmic-term:window:required
        cosmic-edit:window:required
        cosmic-files:window:required
        cosmic-settings:window:required
        cosmic-initial-setup:window:info
        cosmic-store:window:info
        cosmic-player:window:info
        cosmic-viewer:window:info
        cosmic-monitor:window:info
        cosmic-bg:layer:info
        cosmic-panel:layer:info
        cosmic-launcher:layer:info
        cosmic-app-library:layer:info
        cosmic-comp:nested:info
    )
fi

say "== install"
apt-get update -qq
debs=()
if [ "$DIST" != none ]; then
    debs=("$DIST"/*.deb)
fi
# Software rendering: llvmpipe for GL, lavapipe for Vulkan. The harness tools
# (sway, grim, jq) are only for the test, not dependencies of the package.
if ! apt-get install -y --no-install-recommends "${debs[@]}" \
        libgl1-mesa-dri mesa-vulkan-drivers sway grim jq procps dbus \
        > /tmp/apt.log 2>&1; then
    tail -n 30 /tmp/apt.log | tee -a "$REPORT"
    say "== result: install failed"
    exit 1
fi
for d in "${debs[@]}"; do
    say "$(dpkg-deb -f "$d" Package) $(dpkg-deb -f "$d" Version)"
done
say "sway $(dpkg-query -W -f='${Version}' sway), mesa $(dpkg-query -W -f='${Version}' libgl1-mesa-dri)"

# An ordinary user with a fresh home, like a first login.
useradd -m -u 1000 -s /bin/bash tester
install -d -m 0700 -o tester -g tester /run/user/1000
chown -R tester:tester "$OUT"

cat > /tmp/inner.sh <<'INNER'
#!/bin/bash
# Runs as "tester" inside dbus-run-session.
set -u
OUT=$1
shift
REPORT="$OUT/app-smoke.txt"
say() { echo "$*" | tee -a "$REPORT"; }
export XDG_RUNTIME_DIR=/run/user/1000
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export XDG_CURRENT_DESKTOP=COSMIC XDG_SESSION_TYPE=wayland
export RUST_BACKTRACE=1
unset DISPLAY WAYLAND_DISPLAY

mkdir -p ~/.config/sway
cat > ~/.config/sway/config <<'CFG'
output HEADLESS-1 resolution 1280x800
xwayland disable
default_border none
CFG

sway > "$OUT/sway.log" 2>&1 &
sway_pid=$!
for _ in $(seq 1 50); do
    sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n 1)
    wl=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v lock | head -n 1)
    [ -n "$sock" ] && [ -n "$wl" ] && break
    sleep 0.2
done
if [ -z "${sock:-}" ] || [ -z "${wl:-}" ] || ! kill -0 "$sway_pid" 2>/dev/null; then
    say "FAIL: sway did not start"
    tail -n 20 "$OUT/sway.log" | tee -a "$REPORT"
    exit 1
fi
export SWAYSOCK=$sock WAYLAND_DISPLAY=$wl
say "sway running on $WAYLAND_DISPLAY"

# True if a window owned by pid $1 (or a child of it) is mapped in sway.
mapped() {
    local pids
    pids=$({ echo "$1"; pgrep -P "$1"; } | jq -sc .)
    swaymsg -t get_tree |
        jq -e --argjson p "$pids" '[.. | objects | .pid? // empty] | any(.[]; . as $x | $p | index($x))' \
        > /dev/null
}

fails=0
for spec in "$@"; do
    IFS=: read -r name kind need <<< "$spec"
    log="$OUT/$name.log"
    if ! command -v "$name" > /dev/null; then
        say "$(printf '%-22s %-7s %-8s %s' "$name" "$kind" "$need" "MISSING: not installed")"
        [ "$need" = required ] && fails=$((fails + 1))
        continue
    fi
    if [ "$kind" = nested ]; then
        COSMIC_BACKEND=winit "$name" > "$log" 2>&1 &
    else
        "$name" > "$log" 2>&1 &
    fi
    pid=$!
    verdict=""
    if [ "$kind" = layer ]; then
        sleep 8
    else
        for _ in $(seq 1 40); do
            kill -0 "$pid" 2>/dev/null || break
            mapped "$pid" && { verdict=mapped; break; }
            sleep 0.5
        done
        sleep 3
    fi
    if kill -0 "$pid" 2>/dev/null; then
        alive=yes
    else
        wait "$pid"
        alive="no (exit $?)"
    fi
    grim "$OUT/$name.png" 2> /dev/null || true

    if [ "$alive" != yes ]; then
        result="FAIL: exited, $alive"
    elif [ "$kind" != layer ] && [ "$verdict" != mapped ]; then
        result="FAIL: running but no window after 20s"
    else
        result="ok"
    fi
    if [ "$result" != ok ] && [ "$need" = required ]; then
        fails=$((fails + 1))
    fi
    say "$(printf '%-22s %-7s %-8s %s' "$name" "$kind" "$need" "$result")"
    if [ "$result" != ok ]; then
        grep -v '^\s*$' "$log" | tail -n 8 | sed 's/^/    | /' | tee -a "$REPORT"
    fi

    pkill -TERM -P "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
    sleep 1
    pkill -KILL -P "$pid" 2>/dev/null
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
done

swaymsg exit > /dev/null 2>&1
say "== result: $fails required failure(s)"
[ "$fails" -eq 0 ]
INNER
chmod 755 /tmp/inner.sh

say "== programs (name, kind, required?, result)"
su tester -c "cd ~ && dbus-run-session -- /tmp/inner.sh '$OUT' $(printf "'%s' " "${specs[@]}")"
status=$?
chmod -R a+rX "$OUT"
exit "$status"
