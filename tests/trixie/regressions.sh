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
        # this VM; a real GPU does not use it); in a local run (v37) the same
        # in its main thread (the kernel then names cosmic-comp).
        gallium=$(g sudo journalctl -k -S "@$t0" --no-pager -o cat -g "(llvmpipe|cosmic-comp).* segfault .* in libgallium" | grep -c .)
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
# dock adds at its right end: the dock (centred) grows by one 72-pixel item
# between the two shots. (A difference of the two shots would also take in
# stale pixels beside the dock, cosmic-panel#576.)
thumb_click() {
    local before after
    before=$(ctl dock "$OUT/$1.ppm" | awk '{ print $2 }')
    after=$(ctl dock "$OUT/$2.ppm" | awk '{ print $2 }')
    [ $(( after - before )) -ge 20 ] && [ $(( after - before )) -le 60 ] || return 1
    ctl click $(( after - 36 )) 760
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

# Keyboard focus in dialogs (cosmic-edit#210 and its duplicate #494, #625;
# cosmic-files#1518): the keys must go to the dialog, not to what is behind.
reg_dialog_focus() {
    say "== keyboard focus in dialogs: Edit's save question, Files' Open with (cosmic-edit#210, cosmic-files#1518) [$(elapsed)]"
    local d
    gs sh -c 'setsid cosmic-edit < /dev/null > /tmp/edit-df.log 2>&1 &'
    wait_for 15 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 3
    win DF0
    ctl type "hello focus"
    sleep 1
    shot DF0 > /dev/null
    ctl key ctrl-w
    sleep 2
    shot DF1-dialog > /dev/null
    # The dialog: centred in the window (at 211,115 it is 355,250-925,446).
    if gt "$(changed DF0 DF1-dialog $((WX + 144)) $((WY + 135)) $((WX + 714)) $((WY + 331)))" 0.3; then
        ctl key tab
        ctl key ret
        sleep 1
        shot DF2-keys > /dev/null
        if gt "$(changed DF1-dialog DF2-keys $((WX + 15)) $((WY + 80)) $((WX + 830)) $((WY + 130)))" 0.001; then
            known_issue "[focus] with Edit's \"Save changes before closing?\" dialog open, Tab and Enter go into the document behind it (pop-os/cosmic-edit#210, open)"
        elif gt "$(changed DF1-dialog DF2-keys $((WX + 144)) $((WY + 135)) $((WX + 714)) $((WY + 331)))" 0.3; then
            ok "[focus] Edit's save question takes the keyboard (Tab, Enter)"
        else
            fail "[focus] Tab and Enter in Edit's save question changed nothing"
        fi
        # Cancel (if the dialog is still there), then type: the document
        # must take the keys again (cosmic-edit#625).
        if lt "$(changed DF1-dialog DF2-keys $((WX + 144)) $((WY + 135)) $((WX + 714)) $((WY + 331)))" 0.3; then
            ctl click $((WX + 205)) $((WY + 291))
            sleep 1
        fi
        shot DF3-cancelled > /dev/null
        ctl type "Z"
        sleep 1
        shot DF4-typed > /dev/null
        d=$(changed DF3-cancelled DF4-typed $((WX + 15)) $((WY + 80)) $((WX + 830)) $((WY + 200)))
        if gt "$d" 0.0003; then
            ok "[focus] after Cancel the document takes typing again"
        else
            known_issue "[focus] after cancelling Edit's save question typing does nothing (pop-os/cosmic-edit#625, open)"
        fi
        ctl key ctrl-w
        sleep 2
        ctl click $((WX + 550)) $((WY + 291))   # Discard changes
    else
        fail "[focus] Ctrl+W with unsaved changes showed no save question"
    fi
    wait_gone 10 "cosmic-edit closed" pgrep -u tester -x cosmic-edit || g pkill -u tester -x cosmic-edit

    g sh -c 'mkdir -p ~/owtest && echo a > ~/owtest/a.txt && echo b > ~/owtest/b.txt'
    gs sh -c 'setsid cosmic-files /home/tester/owtest < /dev/null > /tmp/files-ow.log 2>&1 &'
    wait_for 15 "cosmic-files running" pgrep -u tester -x cosmic-files
    sleep 3
    win OW0
    ctl click $((WX + 330)) $((WY + 120))        # a.txt
    sleep 1
    ctl click $((WX + 330)) $((WY + 120)) right
    sleep 2
    ctl click $((WX + 386)) $((WY + 174))        # Open with... (second item)
    sleep 3
    shot OW1-dialog > /dev/null
    if gt "$(changed OW0 OW1-dialog $((WX + 144)) $((WY + 25)) $((WX + 714)) $((WY + 440)))" 0.3; then
        ctl key down
        sleep 1
        shot OW2-down > /dev/null
        # The folder's rows show right of the dialog; the apps list inside it.
        if gt "$(changed OW1-dialog OW2-down $((WX + 715)) $((WY + 90)) $((WX + 830)) $((WY + 225)))" 0.05; then
            known_issue "[focus] in Files' \"Open with\" dialog the arrow keys move the selection in the folder behind it; Enter would open that file (pop-os/cosmic-files#1518, open)"
        elif gt "$(changed OW1-dialog OW2-down $((WX + 168)) $((WY + 150)) $((WX + 690)) $((WY + 352)))" 0.005; then
            ok "[focus] Files' \"Open with\" dialog takes the arrow keys"
        else
            fail "[focus] the Down key in Files' \"Open with\" dialog changed nothing"
        fi
        ctl click $((WX + 576)) $((WY + 400))    # Cancel
        sleep 1
    else
        fail "[focus] Files' \"Open with\" dialog did not open"
    fi
    ctl key meta_l-q
    wait_gone 10 "cosmic-files closed" pgrep -u tester -x cosmic-files || g pkill -u tester -x cosmic-files
    g rm -rf /home/tester/owtest
}

# Tray icons (StatusNotifierItem; cosmic-epoch#3217, cosmic-applets#1187):
# a small Ayatana AppIndicator app, the library most tray apps on Debian use,
# shows an icon whose menu works; after a panel restart the icon is back;
# when the app quits the icon goes.
reg_tray() {
    say "== a tray icon: shown, its menu works, back after a panel restart, gone after quitting (cosmic-epoch#3217) [$(elapsed)]"
    local x1 panel start
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gir1.2-ayatanaappindicator3-0.1 > /dev/null 2>&1; then
        fail "[tray] could not install gir1.2-ayatanaappindicator3-0.1 (the test's tray app)"
        return
    fi
    g sh -c 'rm -f /tmp/tray-clicked; cat > /tmp/vmtest-tray.py' <<'EOF'
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3 as AI

ind = AI.Indicator.new("vmtest-tray", "dialog-information", AI.IndicatorCategory.APPLICATION_STATUS)
ind.set_status(AI.IndicatorStatus.ACTIVE)
menu = Gtk.Menu()
item = Gtk.MenuItem(label="VM test item")
item.connect("activate", lambda *_: open("/tmp/tray-clicked", "w").write("yes\n"))
menu.append(item)
menu.show_all()
ind.set_menu(menu)
Gtk.main()
EOF
    ctl click 640 400
    sleep 1
    shot TR0 > /dev/null
    gs sh -c 'setsid python3 /tmp/vmtest-tray.py < /dev/null > /tmp/tray.log 2>&1 &'
    sleep 5
    shot TR1-icon > /dev/null
    # The new icon is the rightmost change in the status area (the icons on
    # its left move over to make room).
    set -- $(ctl bbox "$OUT/TR0.ppm" "$OUT/TR1-icon.ppm" 900 0 1280 32)
    if [ "$1" = none ]; then
        fail "[tray] no icon appeared in the panel ($(g tail -n 2 /tmp/tray.log | tr '\n' ' '))"
        g pkill -f vmtest-tray.py
        return
    fi
    x1=$3
    ok "[tray] the app's tray icon shows in the panel"
    ctl click $((x1 - 7)) 15
    sleep 2
    shot TR2-menu > /dev/null
    ctl click $((x1 - 7)) 70                   # its menu's only item
    sleep 2
    check "[tray] the icon's menu opens and its item runs in the app" g test -e /tmp/tray-clicked
    ctl key esc
    start=$(g date +%s)
    panel=$(g pgrep -u tester -x cosmic-panel)
    g kill "$panel"
    wait_for 30 "a new cosmic-panel" sh -c "pgrep -u tester -x cosmic-panel | grep -v -x $panel"
    sleep 8
    shot TR3-panel-restarted > /dev/null
    add_window "$start" "$(g date +%s)"
    if lt "$(changed TR1-icon TR3-panel-restarted 900 0 1280 32)" 0.005; then
        ok "[tray] after the panel restarts the icon is back"
    else
        fail "[tray] after the panel restarted the tray icon is missing (cosmic-epoch#3217; TR3-panel-restarted.png)"
    fi
    g pkill -f vmtest-tray.py
    sleep 3
    shot TR4-quit > /dev/null
    check "[tray] when the app quits its icon goes" lt "$(changed TR0 TR4-quit 900 0 1280 32)" 0.005
}

# Screen sharing through the ScreenCast portal (xdg-desktop-portal-cosmic
# #384, #389, #403, #407: streams that freeze, portal crashes): the portal's
# picker, then 15 s of the stream while a terminal prints the time every
# 0.2 s; frames must keep coming to the end and show the screen.
reg_screencast() {
    say "== screen sharing: the ScreenCast portal's picker, 15 s of the stream (xdg-desktop-portal-cosmic#384) [$(elapsed)]"
    local portal start n a b c
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gstreamer1.0-pipewire gstreamer1.0-tools > /dev/null 2>&1; then
        fail "[screencast] could not install gstreamer1.0-pipewire and gstreamer1.0-tools (the test's client)"
        return
    fi
    "${SSH[@]}" "cat > /tmp/screencast-client.py" < "$HERE/screencast-client.py"
    # (pgrep -x cannot tell xdg-desktop-portal from -cosmic: 15 characters)
    portal=$(g pgrep -u tester -f '^/usr/libexec/xdg-desktop-portal-cosmic')
    ctl click 640 400
    sleep 1
    shot SC0 > /dev/null
    start=$(g date +%s)
    gs sh -c 'rm -rf /tmp/sc; setsid python3 /tmp/screencast-client.py 15 /tmp/sc < /dev/null > /tmp/sc.log 2>&1 &'
    sleep 4
    shot SC1-picker > /dev/null
    if lt "$(changed SC0 SC1-picker 356 111 924 643)" 0.2; then
        fail "[screencast] the portal showed no picker ($(g cat /tmp/sc.log /tmp/sc/result.txt 2> /dev/null | tail -n 2 | tr '\n' ' '))"
        g pkill -f screencast-client.py
        return
    fi
    ok "[screencast] the portal asks which screen to share"
    ctl click 640 400                          # the screen (Virtual-1)
    sleep 1
    ctl click 866 604                          # Share
    if ! wait_for 15 "the stream started" grep -q '^ok' /tmp/sc/result.txt; then
        fail "[screencast] no stream after Share ($(g cat /tmp/sc/result.txt /tmp/sc.log 2> /dev/null | tail -n 2 | tr '\n' ' '))"
        g pkill -f screencast-client.py
        return
    fi
    ok "[screencast] Share starts a PipeWire stream ($(g cat /tmp/sc/result.txt))"
    gs sh -c 'setsid cosmic-term -e sh -c "while :; do date +%T.%N; sleep 0.2; done" < /dev/null > /dev/null 2>&1 &'
    wait_gone 30 "the recording done" pgrep -f screencast-client.py
    shot SC2-screen > /dev/null
    # Frames per third of the recording: each third must have some (the
    # terminal changes 5 times a second).
    set -- $(g awk '{ if ($1 < 5) a++; else if ($1 < 10) b++; else c++ } END { print a + 0, b + 0, c + 0 }' /tmp/sc/frames.txt 2> /dev/null)
    a=${1:-0} b=${2:-0} c=${3:-0}
    n=$((a + b + c))
    if [ "$a" -ge 10 ] && [ "$b" -ge 10 ] && [ "$c" -ge 10 ]; then
        ok "[screencast] frames keep coming for 15 s ($a, $b, $c in each 5 s)"
    else
        fail "[screencast] the stream stopped or stalled: $a, $b, $c frames in each 5 s ($n in all)"
    fi
    # The frame as a PPM (raw RGB from GStreamer; 1280 pixels make rows
    # without padding), for vmctl diff.
    g sh -c 'gst-launch-1.0 -q filesrc location=/tmp/sc/last.png ! pngdec ! videoconvert ! video/x-raw,format=RGB,width=1280,height=800 ! filesink location=/tmp/sc/last.rgb' > /dev/null 2>&1
    { printf 'P6\n1280 800\n255\n'; g cat /tmp/sc/last.rgb 2> /dev/null; } > "$OUT/SC3-last-frame.ppm"
    if [ -s "$OUT/SC3-last-frame.ppm" ] && lt "$(changed SC2-screen SC3-last-frame)" 0.15; then
        ok "[screencast] the last frame shows the screen (changed $(changed SC2-screen SC3-last-frame) from a screenshot)"
    else
        fail "[screencast] the last frame is not the screen (SC3-last-frame.ppm)"
    fi
    ctl key meta_l-q                           # the terminal
    sleep 2
    add_window "$start" "$(g date +%s)"
    if [ "$(g pgrep -u tester -f '^/usr/libexec/xdg-desktop-portal-cosmic')" = "$portal" ]; then
        ok "[screencast] the portal (xdg-desktop-portal-cosmic) did not crash"
    else
        fail "[screencast] the portal (xdg-desktop-portal-cosmic) crashed or exited during the stream; its last lines and any core dump:"
        g sudo journalctl -S "@$start" --no-pager -o short-monotonic _PID="$portal" 2> /dev/null | tail -n 15 | sed 's/^/    | /' | tee -a "$REPORT"
        g sudo journalctl -S "@$start" --no-pager -o cat -t systemd-coredump 2> /dev/null | grep -A12 "xdg-desktop-por" | head -n 25 | sed 's/^/    | /' | tee -a "$REPORT"
        g tail -n 5 /tmp/sc.log 2> /dev/null | sed 's/^/    | client: /' | tee -a "$REPORT"
    fi
}

# Chromium leaving full screen by itself after a second or two (cosmic-comp
# #2677, #2685, closed; earlier #1642): a page with an animation (as a video)
# goes full screen on a key press, as YouTube's "f", and with F11; it must
# still be full screen 7 s later. On Wayland and through Xwayland.
reg_chromium_fullscreen() {
    say "== Chromium full screen stays (page and F11; Wayland and X11) (cosmic-comp#2677) [$(elapsed)]"
    local d mode top
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq chromium > /dev/null 2>&1; then
        fail "[chromium] could not install chromium"
        return
    fi
    g sh -c 'cat > /tmp/fs.html' <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>vmtest fullscreen</title>
<style>html,body{margin:0;height:100%;background:#20a040}canvas{display:block;width:100%;height:100%}</style>
</head><body><canvas id="c"></canvas>
<script>
const c = document.getElementById("c"), x = c.getContext("2d");
function draw(t) {
  c.width = innerWidth; c.height = innerHeight;
  x.fillStyle = "#20a040"; x.fillRect(0, 0, c.width, c.height);
  x.fillStyle = "#ffffff"; x.fillRect((t / 5) % c.width, c.height / 2 - 20, 40, 40);
  requestAnimationFrame(draw);
}
requestAnimationFrame(draw);
document.addEventListener("keydown", e => { if (e.key === "f") document.documentElement.requestFullscreen(); });
</script></body></html>
EOF
    d=$(g sh -c 'tr "\0" "\n" < /proc/$(pgrep -u tester -x cosmic-panel)/environ | sed -n "s/^DISPLAY=//p"')
    # fs_top KEY NAME: press KEY, wait 7 s; the share of the screen in the
    # page's green (near 1.0: full screen).
    fs_top() { ctl key "$1"; sleep 7; ctl shot "$OUT/$2.png" | sed 's/.*top=//'; }
    for mode in wayland x11; do
        # A new profile for each (no first-run questions with these flags).
        gs env DISPLAY="${d:-:1}" sh -c "setsid chromium --ozone-platform=$mode --no-first-run --password-store=basic --user-data-dir=/tmp/vmtest-chromium-$mode --disable-gpu file:///tmp/fs.html < /dev/null > /tmp/chr-$mode.log 2>&1 &"
        sleep 12
        if lt "$(ctl shot "$OUT/CR-$mode-0.png" | sed 's/.*top=//')" 0.15; then
            fail "[chromium] Chromium ($mode) showed no window ($(g tail -n 1 /tmp/chr-$mode.log))"
            g pkill -f "user-data-dir=/tmp/vmtest-chromium-$mode"
            continue
        fi
        top=$(fs_top f CR-$mode-page)
        check "[chromium] $mode: the page's full screen (as a video's) stays for 7 s (green covers $top)" gt "$top" 0.95
        ctl key esc
        sleep 2
        top=$(fs_top f11 CR-$mode-f11)
        check "[chromium] $mode: F11 full screen stays for 7 s (green covers $top)" gt "$top" 0.95
        ctl key f11
        sleep 2
        g pkill -f "user-data-dir=/tmp/vmtest-chromium-$mode"
        wait_gone 15 "chromium closed" pgrep -f "user-data-dir=/tmp/vmtest-chromium-$mode"
    done
}

# Typing through an input method (fcitx5 with pinyin; cosmic-comp#2941,
# closed: keys fcitx5 hands back, Enter and Backspace, ignored; cosmic-epoch
# #3966, open: Caps Lock reset by the next key while fcitx5 runs). fcitx5
# hooks into Xwayland's start once installed, so it is purged afterwards.
reg_fcitx5() {
    say "== an input method: fcitx5 pinyin in COSMIC Edit; Enter, Backspace, Caps Lock through it (cosmic-comp#2941, cosmic-epoch#3966) [$(elapsed)]"
    local text
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends fcitx5 fcitx5-pinyin > /dev/null 2>&1; then
        fail "[im] could not install fcitx5 and fcitx5-pinyin"
        return
    fi
    g sh -c 'mkdir -p ~/.config/fcitx5 && cat > ~/.config/fcitx5/profile' <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
EOF
    gs sh -c 'setsid fcitx5 -d --replace < /dev/null > /tmp/fcitx5.log 2>&1 &'
    sleep 5
    gs sh -c 'setsid cosmic-edit < /dev/null > /tmp/edit-im.log 2>&1 &'
    wait_for 15 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 3
    win IM0
    ctl key ctrl-spc                         # pinyin on
    sleep 1
    ctl type "nihao"
    sleep 1
    shot IM1-candidates > /dev/null
    ctl key spc                              # the first candidate
    sleep 1
    ctl key ctrl-spc                         # back to keyboard-us (still through fcitx5)
    sleep 1
    ctl type "xy"
    ctl key backspace
    ctl key ret
    ctl type "z"
    ctl key caps_lock
    ctl type "ab"
    ctl key caps_lock
    sleep 1
    shot IM2-typed > /dev/null
    ctl key ctrl-a
    ctl key ctrl-c
    sleep 1
    text=$(gs wl-paste -n 2> /dev/null)
    say "  typed: $(printf '%s' "$text" | tr '\n' '|')"
    case $text in 你好*) ok "[im] fcitx5 pinyin: \"nihao\" and Space type 你好 in COSMIC Edit" ;;
                  *) fail "[im] fcitx5 pinyin did not type 你好 (IM1-candidates.png)" ;; esac
    case $text in *"x"$'\n'"z"*) ok "[im] Backspace and Enter work while fcitx5 runs (cosmic-comp#2941)" ;;
                  *) fail "[im] Backspace or Enter do not work while fcitx5 runs (cosmic-comp#2941)" ;; esac
    case $text in
        *AB) ok "[im] Caps Lock works while fcitx5 runs" ;;
        *ab) known_issue "[im] while fcitx5 runs, Caps Lock is reset by the next key (\"ab\" instead of \"AB\"; without fcitx5 it works; pop-os/cosmic-epoch#3966, open)" ;;
        *) fail "[im] Caps Lock and \"ab\" typed neither AB nor ab" ;;
    esac
    g pkill -u tester -x fcitx5
    sleep 1
    ctl key ctrl-w
    sleep 2
    ctl click $((WX + 550)) $((WY + 291))    # Discard changes
    wait_gone 10 "cosmic-edit closed" pgrep -u tester -x cosmic-edit || g pkill -u tester -x cosmic-edit
    g sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --autoremove fcitx5 fcitx5-pinyin > /dev/null 2>&1
    # (Installed, it hooks into every Xwayland start: Xwayland-session.d.)
    check "[im] fcitx5 is purged again" test -z "$(g dpkg-query -W -f='${db:Status-Status}\n' fcitx5 2> /dev/null | grep -x -E 'installed|config-files')$(g ls /etc/xdg/Xwayland-session.d/20-fcitx-x11 2> /dev/null)"
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
    reg_dialog_focus
    reg_tray
    reg_screencast
    reg_chromium_fullscreen
    reg_fcitx5
}
