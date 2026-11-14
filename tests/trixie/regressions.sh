# Checks for the kinds of bugs that keep coming back in COSMIC's issue
# trackers (pop-os/cosmic-epoch and the component repositories), ranked by how
# often they are reported and duplicated. Each check names the issues it
# guards against. Sourced by vm-session.sh after criteria.sh (same helpers);
# ACCEPTANCE.md lists them under "Recurring upstream bugs".
#
# Test tools: xclip and xterm (the X11 side of the clipboard).

# recover_session WHY: end tester's session through logind and log in again,
# so that the next checks start from a fresh desktop.
recover_session() {
    local start
    start=$(g date +%s)
    say "  a new session: $1"
    g sudo loginctl terminate-session "$(session_id)"
    wait_gone 30 "tester's session gone" pgrep -u tester -x cosmic-comp
    wait_for 60 "login screen back" pgrep -u cosmic-greeter -x cosmic-greeter
    sleep 6
    log_in
    add_window "$start" "$(g date +%s)"
}

# Volume changes keep the output device and the balance set in Settings
# (cosmic-settings#1101 and its duplicates #2034, cosmic-applets#1277,
# cosmic-osd#188, cosmic-panel#575).
reg_volume() {
    say "== volume keys and the panel keep the output and the balance (cosmic-settings#1101) [$(elapsed)]"
    local snd l0 r0 out
    gs pactl load-module module-null-sink sink_name=vmtest_null > /dev/null
    sleep 2
    snd=$(gs pactl get-default-sink)
    case $snd in vmtest_null) fail "[sound] a new output became the default by itself"; gs pactl set-default-sink "$(gs pactl list short sinks | awk '$2 != "vmtest_null" { print $2; exit }')"; snd=$(gs pactl get-default-sink) ;; esac
    gs pactl set-sink-volume @DEFAULT_SINK@ 40%
    ctl key meta_l-2
    sleep 2
    settings_page sound SB0
    wclick 664 263                       # Balance: towards Left
    sleep 2
    # lr: "LEFT RIGHT" in percent.
    lr() { gs pactl get-sink-volume @DEFAULT_SINK@ | head -n 1 | grep -o '[0-9]*%' | tr -d % | head -n 2 | tr '\n' ' '; }
    set -- $(lr)
    l0=$1 r0=$2
    if [ -z "$r0" ] || ! gt "$l0" "$(( r0 + 5 ))"; then
        fail "[sound] the Balance slider in Settings did not move the balance ($(lr))"
    else
        for step in "volume-up key:ctl key volumeup" "volume-down key:ctl key volumedown" \
                    "scroll up on the panel icon:ctl scroll 1089 15 up 1" "scroll down on the panel icon:ctl scroll 1089 15 down 1"; do
            ${step#*:}
            sleep 2
            set -- $(lr)
            out=$(gs pactl get-default-sink)
            # The balance is the ratio of the channels: kept within 15%.
            if [ "$out" = "$snd" ] && [ "${2:-0}" -gt 0 ] && [ "$1" != "$l0" ] &&
               awk -v a="$l0" -v b="$r0" -v c="$1" -v d="$2" 'BEGIN { r = (c / d) / (a / b); exit !(r > 0.85 && r < 1.15) }'; then
                ok "[sound] the ${step%%:*} changes the volume and keeps the output and the balance ($l0/$r0 -> $1/$2)"
            else
                fail "[sound] the ${step%%:*}: $l0/$r0 -> ${1:-?}/${2:-?}, output $out (was $snd)"
            fi
            l0=$1 r0=$2
        done
    fi
    wclick 696 263                       # Balance: centre
    sleep 2
    wclick 400 20                        # focus Settings (the panel had the scroll)
    ctl key meta_l-q
    wait_gone 10 "Settings closed" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)' || g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    gs pactl unload-module module-null-sink
    gs pactl set-sink-volume @DEFAULT_SINK@ 40%
    ctl key meta_l-1
    sleep 2
}

# The workspaces overview, opened and closed many times, with a window open
# (cosmic-epoch#2978, #2997, cosmic-workspaces-epoch#264, #340).
reg_overview() {
    say "== the workspaces overview, 20 times (cosmic-epoch#2978) [$(elapsed)]"
    local comp i t0 shown=0 dumps panics
    ctl key meta_l-2
    sleep 2
    ctl key meta_l-t
    sleep 3
    shot WO0 > /dev/null
    comp=$(g pgrep -u tester -x cosmic-comp)
    t0=$(g date +%s)
    for i in $(seq 20); do
        ctl key meta_l-w
        sleep 1.5
        shot WO1-overview > /dev/null
        gt "$(changed WO0 WO1-overview)" 0.05 && shown=$((shown + 1))
        ctl key esc
        sleep 1
    done
    sleep 3
    # Its crashes are reported here, not again by check_journal.
    add_window "$t0" "$(g date +%s)"
    shot WO2 > /dev/null
    dumps=$(g sh -c "coredumpctl list --no-legend -S @$t0 /usr/bin/cosmic-workspaces 2> /dev/null | wc -l")
    # pop-os/cosmic-workspaces-epoch#340: after a capture protocol error the
    # overview panics in wgpu, in the software renderer or in screencopy.rs.
    panics=$(g sudo journalctl -S "@$t0" --no-pager -o cat -g "panicked at .*(wgpu_core\.rs|tiny_skia/src/window/compositor\.rs:144:|screencopy\.rs)" | grep -c .)
    say "  the overview showed $shown of 20 times; cosmic-workspaces crashed $dumps time(s)"
    if [ "$dumps" -eq 0 ] && [ "$shown" -eq 20 ]; then
        ok "[workspaces] Super+W shows the overview and Escape closes it, 20 times, without a crash"
    elif [ "$dumps" -gt 0 ] && [ "$panics" -gt 0 ]; then
        # (A dying process's last output may not reach the journal: some
        # crashes have no panic message.)
        known_issue "[workspaces] the workspaces overview crashed $dumps time(s) in 20 (shown $shown; $panics with the panic of pop-os/cosmic-workspaces-epoch#340, after a capture protocol error)"
    else
        fail "[workspaces] the overview showed $shown of 20 times, cosmic-workspaces crashed $dumps time(s) ($panics of them as in cosmic-workspaces-epoch#340)"
    fi
    local comp2 gallium
    comp2=$(g pgrep -u tester -x cosmic-comp)
    if [ "$comp2" = "$comp" ] && lt "$(changed WO0 WO2)" 0.01; then
        ok "[workspaces] afterwards the compositor and the desktop are as before"
    elif [ "$comp2" = "$comp" ]; then
        fail "[workspaces] afterwards the desktop is not as before (screen changed $(changed WO0 WO2))"
    else
        # Seen once in CI (build 15): while the overview crashed and came back,
        # cosmic-comp logged "Erroneous EGL call didn't set EGLError" and died
        # of a SIGSEGV in llvmpipe's threads (Mesa's software renderer, as in
        # this VM; a real GPU does not use it).
        gallium=$(g sudo journalctl -k -S "@$t0" --no-pager -o cat -g "llvmpipe.* segfault .* in libgallium" | grep -c .)
        if [ "$gallium" -gt 0 ]; then
            known_issue "[workspaces] cosmic-comp crashed while the overview crashed and restarted: SIGSEGV in Mesa's software renderer (llvmpipe, libgallium) after \"Erroneous EGL call\"; the session restarted the compositor, the open windows were lost; not confirmed upstream"
        else
            fail "[workspaces] the compositor restarted ($comp -> ${comp2:-none})"
        fi
        # The windows are gone and the panel's applets restarted: the later
        # checks start from a fresh session instead.
        recover_session "the compositor restarted"
        return
    fi
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# thumb_click BEFORE AFTER: click the minimized window's thumbnail, which the
# dock adds at its right end (found by comparing the dock in two shots).
thumb_click() {
    set -- $(ctl bbox "$OUT/$1.ppm" "$OUT/$2.ppm" 0 725 1280 798)
    [ "$1" != none ] || return 1
    ctl click $(( $3 - 25 )) 760
}

# Maximized and tiled windows come back as they were after minimizing
# (cosmic-epoch#2743, cosmic-comp#2524, #2132, #1972). Restored from the
# dock's thumbnail (Alt+Tab would pick other windows too).
reg_minimize() {
    say "== minimize and restore a maximized and a tiled window (cosmic-epoch#2743) [$(elapsed)]"
    local comp
    comp=$(g pgrep -u tester -x cosmic-comp)
    ctl key meta_l-2
    sleep 2
    shot MN-empty > /dev/null            # the dock without the thumbnail
    ctl key meta_l-t
    sleep 3
    ctl key meta_l-m
    sleep 2
    shot MN0-maximized > /dev/null
    ctl click 1175 56                    # the maximized window's minimize button
    sleep 2
    shot MN1-minimized > /dev/null
    if gt "$(changed MN0-maximized MN1-minimized 0 80 1280 720)" 0.3 && thumb_click MN-empty MN1-minimized; then
        sleep 2
        shot MN2 > /dev/null
        check "[wm] a minimized maximized window comes back maximized" lt "$(changed MN0-maximized MN2 0 80 1280 720)" 0.01
    else
        fail "[wm] the maximized window's minimize button did not minimize it to the dock"
    fi
    ctl key meta_l-m
    sleep 2
    # Two tiled windows: minimize one, the other fills the screen, then back.
    ctl key meta_l-t
    sleep 3
    ctl key meta_l-y
    sleep 3
    shot MN4-tiled > /dev/null
    set -- $(box_of MN4-tiled)
    if [ "$1" != none ] && [ "$3" -lt 700 ]; then
        ctl click $(( $3 - 105 )) $(( $2 + 24 ))
        sleep 2
        shot MN5-minimized > /dev/null
        if gt "$(changed MN4-tiled MN5-minimized)" 0.02 && thumb_click MN4-tiled MN5-minimized; then
            sleep 2
            shot MN6 > /dev/null
            check "[wm] a minimized tiled window comes back to its tile" lt "$(changed MN4-tiled MN6)" 0.01
        else
            fail "[wm] the tiled window did not minimize to the dock"
        fi
    else
        fail "[wm] Super+Y did not tile the two windows ($*)"
    fi
    ctl key meta_l-y
    sleep 2
    check "[wm] the compositor did not restart" test "$(g pgrep -u tester -x cosmic-comp)" = "$comp"
    ctl key meta_l-q
    sleep 1
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# A notification that went away does not block clicks where it was
# (cosmic-epoch#2726); a burst of notifications (cosmic-notifications#170).
reg_notifications() {
    say "== notifications: no dead area after one goes; a burst of 20 (cosmic-epoch#2726) [$(elapsed)]"
    local pid i
    ctl key meta_l-2
    sleep 2
    g sh -c 'printf "line one\nline two\nline three\n" > /tmp/notify-edit.txt'
    gs sh -c 'setsid cosmic-edit /tmp/notify-edit.txt < /dev/null > /dev/null 2>&1 &'
    wait_for 20 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 4
    ctl key meta_l-m
    sleep 2
    shot NT0 > /dev/null
    notify "click-through test" 3000
    sleep 1
    shot NT1-shown > /dev/null
    sleep 8
    shot NT2-gone > /dev/null
    if gt "$(changed NT0 NT1-shown 960 40 1280 170)" 0.1 && lt "$(changed NT0 NT2-gone 960 40 1280 170)" 0.01; then
        ctl click 1100 140 right         # where it was, over Edit's text
        sleep 2
        shot NT3-menu > /dev/null
        if gt "$(changed NT2-gone NT3-menu 860 140 1100 360)" 0.3; then
            ok "[notify] where a notification was, a click reaches the window below once it is gone"
        else
            fail "[notify] after a notification went away, a click where it was did not reach the window below"
        fi
        ctl key esc
        sleep 1
    else
        fail "[notify] the notification did not show and go away by itself (3 s)"
    fi
    pid=$(g pgrep -u tester -f '^(/usr/bin/)?cosmic-notifications$')
    # (Waits for these senders only: vm-session.sh has QEMU in the background.)
    local senders=
    for i in $(seq 20); do notify "burst $i" 4000 & senders+=" $!"; done
    wait $senders
    sleep 2
    shot NT4-burst > /dev/null
    sleep 14
    shot NT5 > /dev/null
    if [ "$(g pgrep -u tester -f '^(/usr/bin/)?cosmic-notifications$')" = "$pid" ] && lt "$(changed NT2-gone NT5)" 0.01; then
        ok "[notify] 20 notifications at once: no crash, all gone again"
    else
        fail "[notify] after 20 notifications at once: daemon $pid -> $(g pgrep -u tester -f '^(/usr/bin/)?cosmic-notifications$'), screen changed $(changed NT2-gone NT5)"
    fi
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# The clipboard between X11 and Wayland apps, 300 KiB each way: X11
# transfers of 256 KiB and more once gained 4 bytes (cosmic-comp#2717). X11
# apps see the clipboard while one of them has the focus (cosmic-comp does
# not let them read it in the background).
reg_clipboard_x11() {
    say "== clipboard between X11 and Wayland, 300 KiB (cosmic-comp#2717) [$(elapsed)]"
    local d r
    if ! g sh -c 'command -v xclip && command -v xterm' > /dev/null; then
        say "  xclip or xterm not installed: skipped"
        return
    fi
    d=$(g sh -c 'tr "\0" "\n" < /proc/$(pgrep -u tester -x cosmic-panel)/environ | sed -n "s/^DISPLAY=//p"')
    ctl key meta_l-2
    sleep 2
    gs env DISPLAY="${d:-:1}" sh -c 'setsid xterm < /dev/null > /dev/null 2>&1 &'
    wait_for 20 "xterm running" pgrep -u tester -x xterm
    sleep 3
    g sh -c 'head -c 230000 /dev/urandom | base64 > /tmp/clip300k'
    r=$(gs env DISPLAY="${d:-:1}" sh -c '
        f=/tmp/clip300k
        wl-copy < $f > /dev/null 2>&1; sleep 1
        timeout 10 xclip -selection clipboard -t UTF8_STRING -o > /tmp/clip-x 2> /dev/null
        printf "%s " "$(wc -c < /tmp/clip-x) $(cmp -s /tmp/clip-x $f && echo same || echo different)"
        timeout 10 xclip -selection clipboard -i -loops 1 < $f & sleep 1
        timeout 10 wl-paste -n > /tmp/clip-w 2> /dev/null
        printf "%s" "$(wc -c < /tmp/clip-w) $(cmp -s /tmp/clip-w $f && echo same || echo different)"
        wait')
    set -- $r
    say "  of $(g sh -c 'wc -c < /tmp/clip300k') bytes: Wayland to X11 $1 ($2), X11 to Wayland $3 ($4)"
    check "[clipboard] 300 KiB copied in a Wayland app arrive unchanged in an X11 app" test "$2" = same
    check "[clipboard] 300 KiB copied in an X11 app arrive unchanged in a Wayland app" test "$4" = same
    g pkill -u tester -x xterm
    g sh -c 'pkill -u tester -x wl-copy; rm -f /tmp/clip300k /tmp/clip-x /tmp/clip-w'
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# Shortcuts with a Cyrillic layout (cosmic-epoch#2701: Super shortcuts
# stopped working; #3264, open: Ctrl shortcuts in the terminal), as Debian sets
# it up for Russian: us,ru, switched with Super+Space.
reg_layout_cyrillic() {
    say "== shortcuts with the Russian layout active (cosmic-epoch#2701, #3264) [$(elapsed)]"
    local n
    ctl key meta_l-2
    sleep 2
    g sh -c 'printf "cyrillic test\n" > /tmp/cyrillic.txt'
    gs sh -c 'setsid cosmic-edit /tmp/cyrillic.txt < /dev/null > /dev/null 2>&1 &'
    wait_for 20 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 4
    xkb_layout us,ru
    sleep 3
    shot CY0 > /dev/null
    ctl key meta_l-spc
    sleep 2
    shot CY1-ru > /dev/null
    if gt "$(changed CY0 CY1-ru 960 0 1000 30)" 0.05; then
        ok "[layout] Super+Space switches to the second layout (the panel shows it)"
    else
        ctl click 981 15                 # the layout applet: which layouts it knows
        sleep 2
        shot CY1-applet > /dev/null
        ctl key esc
        fail "[layout] Super+Space did not switch to Russian (the layouts the panel knows: CY1-applet.png)"
    fi
    ctl key ctrl-end
    ctl type "ab"
    ctl key ctrl-s
    sleep 2
    check "[layout] with Russian active the keys A and B type ф and и" test "$(g tail -n 1 /tmp/cyrillic.txt)" = "фи"
    gs sh -c 'printf before | wl-copy > /dev/null 2>&1'
    ctl key ctrl-a ctrl-c
    sleep 1
    case "$(gs timeout 5 wl-paste -n 2>&1)" in
        cyrillic*) ok "[layout] Ctrl+A, Ctrl+C work with Russian active (COSMIC Edit)" ;;
        *) fail "[layout] Ctrl+A, Ctrl+C did not copy with Russian active ($(gs timeout 5 wl-paste -n 2>&1 | head -c 40))" ;;
    esac
    n=$(g pgrep -c -u tester -x cosmic-term)
    ctl key meta_l-t
    if wait_for 10 "a new terminal" sh -c "test \$(pgrep -c -u tester -x cosmic-term) -gt $n"; then
        ok "[layout] Super+T works with Russian active"
        sleep 2
        gs sh -c 'printf pasted-in-ru | wl-copy > /dev/null 2>&1'
        ctl key meta_l-spc               # US, to type the command
        sleep 1
        ctl type "cat > /tmp/cyrillic-paste.txt"
        ctl key ret
        ctl key meta_l-spc               # Russian again
        sleep 1
        ctl key ctrl-shift-v
        sleep 1
        ctl key ret ctrl-d
        sleep 1
        check "[layout] Ctrl+Shift+V pastes in the terminal with Russian active" test "$(g cat /tmp/cyrillic-paste.txt)" = pasted-in-ru
        ctl key meta_l-q
        sleep 2
    else
        fail "[layout] Super+T did nothing with Russian active"
    fi
    xkb_layout us
    sleep 2
    ctl key meta_l-q
    sleep 2
    g sh -c 'pkill -u tester -x wl-copy; rm -f /tmp/cyrillic.txt /tmp/cyrillic-paste.txt'
    ctl key meta_l-1
    sleep 2
}

# The compositor does not keep buffers or memory of closed windows
# (cosmic-comp#2073, #2072, cosmic-launcher#419, cosmic-workspaces-epoch#324).
reg_leaks() {
    say "== 20 windows and 10 overviews opened and closed: compositor memory (cosmic-comp#2073) [$(elapsed)]"
    local a b i t0
    # memfd FDS RSS(kB) of cosmic-comp
    comp_mem() {
        g sh -c 'p=$(pgrep -u tester -x cosmic-comp); echo $(ls -l /proc/$p/fd | grep -c memfd) $(ls /proc/$p/fd | wc -l) $(awk "/VmRSS/ { print \$2 }" /proc/$p/status)'
    }
    ctl key meta_l-2
    sleep 2
    t0=$(g date +%s)
    a=$(comp_mem)
    for i in $(seq 20); do
        ctl key meta_l-t
        sleep 2
        ctl key meta_l-q
        sleep 1
    done
    for i in $(seq 10); do
        ctl key meta_l-w
        sleep 1.5
        ctl key esc
        sleep 1
    done
    sleep 3
    # The overview's crashes (cosmic-workspaces-epoch#340) are reported by
    # reg_overview, not again by check_journal.
    add_window "$t0" "$(g date +%s)"
    b=$(comp_mem)
    set -- $a $b
    say "  cosmic-comp: memfd $1 -> $4, file descriptors $2 -> $5, memory $(( $3 / 1024 )) -> $(( $6 / 1024 )) MB"
    if [ $(( $4 - $1 )) -le 10 ] && [ $(( $5 - $2 )) -le 20 ] && [ $(( ($6 - $3) / 1024 )) -le 300 ]; then
        ok "[leak] the compositor keeps no buffers or file descriptors of closed windows"
    else
        fail "[leak] the compositor grows with each window: memfd $1 -> $4, fds $2 -> $5, memory $(( $3 / 1024 )) -> $(( $6 / 1024 )) MB"
    fi
    ctl key meta_l-1
    sleep 2
}

# CPU while idle, locked and after unlocking (cosmic-epoch#3733: the
# compositor and the panel busy while locked; cosmic-comp#2169: a render loop
# after unlocking).
reg_idle_cpu() {
    say "== CPU of the COSMIC processes: idle, locked, after unlocking (cosmic-epoch#3733) [$(elapsed)]"
    local idle locked after start
    # cpu_ticks: "PID:NAME TICKS" of tester's COSMIC processes.
    cpu_ticks() {
        g sh -c 'for p in $(pgrep -u tester -f "^(/usr/bin/|/usr/libexec/)?(cosmic-|xdg-desktop-portal-cosmic)"); do s=$(cat /proc/$p/stat 2> /dev/null) || continue; s=${s#*) }; set -- $s; echo "$p:$(cat /proc/$p/comm) $(( ${12} + ${13} ))"; done' | sort
    }
    # cpu_over SECONDS: "NAME PERCENT" of those above 5% of one CPU.
    cpu_over() {
        local x y
        x=$(cpu_ticks)
        sleep "$1"
        y=$(cpu_ticks)
        join <(echo "$x") <(echo "$y") | awk -v s="$1" '{ p = ($3 - $2) / s; if (p > 5) { sub(/^[0-9]+:/, "", $1); printf "%s %.0f%%, ", $1, p } }'
    }
    ctl key meta_l-1
    sleep 1
    ctl click 640 400
    sleep 5
    idle=$(cpu_over 20)
    if [ -z "$idle" ]; then ok "[cpu] idle, no COSMIC process uses more than 5% of a CPU"; else fail "[cpu] idle: ${idle%, }"; fi
    start=$(g date +%s)
    ctl key meta_l-esc
    sleep 5
    locked=$(cpu_over 20)
    unlock CU-unlocked
    if [ -z "$locked" ]; then
        ok "[cpu] locked, no COSMIC process uses more than 5% of a CPU"
    elif [ "${locked%% *}" = cosmic-comp ] && ! echo "$locked" | grep -q -v -E '^cosmic-comp [0-9]+%, $'; then
        known_issue "[cpu] while the screen is locked cosmic-comp keeps a CPU busy (${locked%, }; pop-os/cosmic-epoch#3733)"
    else
        fail "[cpu] locked: ${locked%, }"
    fi
    after=$(cpu_over 20)
    if [ -z "$after" ]; then ok "[cpu] after unlocking the CPU use drops again"; else fail "[cpu] after unlocking: ${after%, } (cosmic-comp#2169)"; fi
    add_window "$start" "$(g date +%s)"
}

regressions() {
    reg_volume
    reg_overview
    reg_minimize
    reg_notifications
    reg_clipboard_x11
    reg_layout_cyrillic
    reg_leaks
    reg_idle_cpu
}
