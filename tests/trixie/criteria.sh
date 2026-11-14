# What Fedora's release criteria and the openQA desktop suites of Fedora,
# openSUSE and GNOME check, and COSMIC's own checklists do not.
# Sourced by vm-session.sh after acceptance.sh (same helpers). ACCEPTANCE.md
# lists each item with its source; the tags are [wm], [console], [open],
# [apps], [keyring], [power], [panel], [layout], [toolkit], [autostart],
# [settings-wallpaper], [settings-time], [settings-apps], [settings-appearance],
# [settings-about], [idle], [suspend], [language], [password], [notify],
# [graphics], [users], [archive], [panel-advanced], [print], [store],
# [autologin].

# lt A B: A < B (numbers with decimals)

# box_of SHOT: "X0 Y0 X1" of the focused window (its accent border), or none.
# (The bottom edge is not used: the dock hides it on tall windows.)
box_of() {
    set -- $(ctl winbox "$OUT/$1.ppm")
    if [ "$1" = none ]; then echo none; else echo "$1 $2 $3"; fi
}
# near A B: two "X0 Y0 X1" boxes agree within 6 pixels each.
near() {
    [ "$1" != none ] && [ "$2" != none ] || return 1
    local _i _d
    set -- $1 $2
    for _i in 1 2 3; do
        eval "_d=\$(( \${$_i} - \${$((_i + 3))} ))"
        [ "${_d#-}" -le 6 ] || return 1
    done
}

crit_wm() {
    say "== window management: two terminals on workspace 2 (Fedora: window manager functionality) [$(elapsed)]"
    local a b n
    # Workspace 2 is empty (workspace 1 has the windows of the steps before),
    # so tiling and the comparisons see only these two windows.
    ctl key meta_l-2
    sleep 2
    ctl key meta_l-t
    sleep 3
    ctl key meta_l-t
    sleep 3
    shot M0 > /dev/null
    a=$(box_of M0)
    b=none
    if [ "$a" = none ]; then fail "[wm] no focused window after opening two terminals"; return; fi

    ctl key meta_l-m
    sleep 2
    shot M1 > /dev/null
    check "[wm] Super+M maximizes the window" gt "$(changed M0 M1 0 40 200 700)" 0.5
    ctl key meta_l-m
    sleep 2
    shot M2 > /dev/null
    check "[wm] Super+M again restores it" near "$a" "$(box_of M2)"

    ctl key meta_l-f11
    sleep 2
    shot M3 > /dev/null
    check "[wm] Super+F11 makes it full screen (panel and dock hidden)" gt "$(changed M0 M3 320 730 960 790)" 0.2
    ctl key meta_l-f11
    sleep 2
    shot M4 > /dev/null
    if near "$a" "$(box_of M4)" && lt "$(changed M0 M4 320 730 960 790)" 0.05; then
        ok "[wm] Super+F11 again leaves full screen"
    else
        fail "[wm] Super+F11 again did not leave full screen"
    fi

    ctl key alt-tab
    sleep 2
    shot M5 > /dev/null
    b=$(box_of M5)
    if [ "$b" != none ] && ! near "$a" "$b"; then ok "[wm] Alt+Tab focuses the other window"; else fail "[wm] Alt+Tab did not switch windows ($a, then $b)"; fi
    ctl key alt-tab
    sleep 2
    shot M6 > /dev/null
    check "[wm] Alt+Tab again comes back" near "$a" "$(box_of M6)"

    ctl key meta_l-y
    sleep 3
    shot M7 > /dev/null
    set -- $(box_of M7)
    if [ "$1" != none ] && [ "$1" -lt 30 ] && [ "$3" -lt 700 ]; then
        ok "[wm] Super+Y tiles the windows side by side (focused: $1..$3)"
    else
        fail "[wm] Super+Y did not tile the windows (focused: $*)"
    fi
    ctl key meta_l-right
    sleep 1
    shot M8 > /dev/null
    set -- $(box_of M8)
    if [ "$1" != none ] && [ "$1" -gt 600 ]; then ok "[wm] Super+Right focuses the tile on the right"; else fail "[wm] Super+Right did not move the focus (focused: $*)"; fi
    ctl key meta_l-left
    sleep 1
    ctl key meta_l-y
    sleep 3
    shot M9 > /dev/null
    check "[wm] Super+Y again puts the windows back where they were" near "$a" "$(box_of M9)"

    # The title bar's buttons, by the mouse: minimize, then Alt+Tab brings it back.
    set -- $a
    ctl click $(( $3 - 105 )) $(( $2 + 24 ))
    sleep 2
    shot M10 > /dev/null
    if ! near "$a" "$(box_of M10)" && gt "$(changed M9 M10)" 0.05; then ok "[wm] the minimize button hides the window"; else fail "[wm] the minimize button did not hide the window"; fi
    ctl key alt-tab
    sleep 2
    shot M11 > /dev/null
    check "[wm] Alt+Tab brings the minimized window back" near "$a" "$(box_of M11)"

    # Drag the title bar, then the right edge.
    set -- $a
    ctl drag $(( $1 + 300 )) $(( $2 + 24 )) $(( $1 + 200 )) $(( $2 + 124 ))
    sleep 1
    shot M12 > /dev/null
    b=$(box_of M12)
    check "[wm] dragging the title bar moves the window ($a -> $b)" near "$(( $1 - 100 )) $(( $2 + 100 )) $(( $3 - 100 ))" "$b"
    set -- $b
    ctl drag $(( $3 - 1 )) $(( $2 + 150 )) $(( $3 - 101 )) $(( $2 + 150 ))
    sleep 1
    shot M13 > /dev/null
    b=$(box_of M13)
    check "[wm] dragging the right edge resizes it ($* -> $b)" near "$1 $2 $(( $3 - 100 ))" "$b"

    set -- $b
    n=$(g pgrep -c -u tester -x cosmic-term)
    ctl click $(( $3 - 24 )) $(( $2 + 24 ))
    sleep 2
    check "[wm] the close button closes it" test "$(g pgrep -c -u tester -x cosmic-term)" -lt "$n"
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

crit_console() {
    say "== a text console and back (Fedora: virtual consoles) [$(elapsed)]"
    local vt comp
    vt=$(g cat /sys/class/tty/tty0/active)
    comp=$(g pgrep -u tester -x cosmic-comp)
    shot C0 > /dev/null
    local start
    start=$(g date +%s)
    ctl key ctrl-alt-f3
    sleep 3
    check "[console] Ctrl+Alt+F3 switches to the text console" test "$(g cat /sys/class/tty/tty0/active)" = tty3
    shot C1 > /dev/null
    ctl type tester
    ctl key ret
    sleep 3
    ctl type "$PASS"
    ctl key ret
    sleep 5
    ctl type "touch /tmp/on-tty3; exit"
    ctl key ret
    sleep 3
    check "[console] logging in on the console works" g test -e /tmp/on-tty3
    ctl key "ctrl-alt-f${vt#tty}"
    sleep 4
    shot C2 > /dev/null
    check "[console] back on $vt the desktop looks as before" lt "$(changed C0 C2)" 0.01
    check "[console] the same compositor is still running" test "$(g pgrep -u tester -x cosmic-comp)" = "$comp"
    # While the console has the seat, the session loses the sound card and the
    # display for a moment; their complaints are in a known window.
    add_window "$start" "$(( $(g date +%s) + 5 ))"
    shortcuts_work "after the text console"
}

# greeter_console: at the login screen, to a text console and back.
greeter_console() {
    local vt
    vt=$(g cat /sys/class/tty/tty0/active)
    shot G0 > /dev/null
    ctl key ctrl-alt-f3
    sleep 3
    ctl key "ctrl-alt-f${vt#tty}"
    sleep 4
    shot G1 > /dev/null
    check "[console] the login screen comes back after a text console" lt "$(changed G0 G1)" 0.01
}

crit_open() {
    say "== default applications: xdg-open (Fedora: default application functionality) [$(elapsed)]"
    # A text file, a small PNG, a second of sound and a folder.
    g sh -c 'mkdir -p ~/open && echo hello > ~/open/a.txt'
    g python3 -c '
import math, struct, wave, zlib
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
w, h = 64, 48
rows = b"".join(b"\0" + bytes([200, 80, 40]) * w for _ in range(h))
open("/home/tester/open/a.png", "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
s = wave.open("/home/tester/open/a.wav", "wb")
s.setnchannels(1); s.setsampwidth(2); s.setframerate(22050)
s.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(i / 10))) for i in range(22050)))
s.close()
'
    local t f p m
    for t in a.txt:cosmic-edit a.png:cosmic-viewer a.wav:cosmic-player .:cosmic-files; do
        f=/home/tester/open/${t%%:*} p=${t#*:}
        m=$(g xdg-mime query filetype "$f")
        if [ -z "$(g env XDG_CURRENT_DESKTOP=COSMIC xdg-mime query default "$m")" ]; then
            if [ "$m" = audio/vnd.wave ]; then
                known_issue "[open] ${f##*/} ($m, Debian's name for WAV) has no default app: COSMIC's lists name only audio/x-wav"
            else
                fail "[open] ${f##*/} ($m) has no default app"
            fi
            continue
        fi
        shot O0 > /dev/null
        gs env XDG_CURRENT_DESKTOP=COSMIC sh -c "setsid xdg-open $f < /dev/null > /dev/null 2>&1 &"
        if wait_for 20 "$p running" pgrep -u tester -x "$p"; then
            sleep 3
            shot "O-${p#cosmic-}" > /dev/null
            if gt "$(changed O0 "O-${p#cosmic-}")" 0.05; then ok "[open] ${f##*/} opens in $p"; else fail "[open] $p runs, but no window for ${f##*/}"; fi
            ctl key meta_l-q
            wait_gone 10 "$p closed" pgrep -u tester -x "$p" || fail "[open] Super+Q did not close $p"
        else
            fail "[open] xdg-open ${f##*/} did not start $p"
        fi
    done
    p=$(g env XDG_CURRENT_DESKTOP=COSMIC xdg-mime query default x-scheme-handler/https)
    if [ -n "$p" ] && g test -e "/usr/share/applications/${p%%;*}"; then
        say "  web links open in ${p%%;*}"
    else
        say "  no web browser installed: links and Super+B open nothing (COSMIC's default list names firefox-esr)"
    fi
}

crit_apps() {
    say "== the apps not used above start and close (Fedora: default application functionality) [$(elapsed)]"
    local a
    # ("system monitor" finds Settings' System & Accounts page first.)
    for a in "monitor:cosmic-monitor" "viewer:cosmic-viewer"; do
        shot A0 > /dev/null
        if launch_app "${a%%:*}" "${a#*:}"; then
            shot "A-${a#*:}" > /dev/null
            if gt "$(changed A0 "A-${a#*:}")" 0.05; then ok "[apps] ${a#*:} starts with a window"; else fail "[apps] ${a#*:} runs, but no window"; fi
            ctl key meta_l-q
            wait_gone 10 "${a#*:} closed" pgrep -u tester -x "${a#*:}" || fail "[apps] Super+Q did not close ${a#*:}"
        else
            fail "[apps] ${a#*:} did not start from the launcher"
        fi
    done
}

# keyring_state: "unlocked", "locked", "none" (login collection unusable) or
# "missing" (no PAM module, so nothing unlocks it at login).
keyring_state() {
    if ! g test -e /usr/lib/x86_64-linux-gnu/security/pam_gnome_keyring.so; then echo missing; return; fi
    case "$(gs busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked 2>&1)" in
        "b false") echo unlocked ;;
        "b true") echo locked ;;
        *) echo none ;;
    esac
}

# crit_keyring first|again: the login keyring is unlocked by the login password
# and keeps secrets; "again" (a later login) also tests the unlock prompt.
crit_keyring() {
    say "== desktop keyring, $1 login (Fedora: desktop keyring) [$(elapsed)]"
    local s
    s=$(keyring_state)
    case "$s" in
        missing)
            known_issue "[keyring] nothing unlocks the keyring at login: libpam-gnome-keyring not installed (newer builds of the package recommend it)"
            return ;;
        none)
            if [ "$1" = first ]; then
                known_issue "[keyring] on the first login the new login keyring cannot be used until the next login (PAM made it; storing a secret waits for a prompt that closes at once): looks like gnome-keyring's first-login bug, not COSMIC's"
            else
                fail "[keyring] the login keyring is not available after logging in"
            fi
            return ;;
        locked) fail "[keyring] the login password did not unlock the login keyring"; return ;;
    esac
    ok "[keyring] the login password unlocked the login keyring"
    gs sh -c "printf 's3cret-$1' | timeout 15 secret-tool store --label=vmtest service vmtest login $1"
    check "[keyring] a secret is stored and read back without a prompt" \
        test "$(gs timeout 10 secret-tool lookup service vmtest login "$1")" = "s3cret-$1"
    [ "$1" = again ] || return
    # Lock it: asking for the secret must show the unlock prompt, and the
    # password typed there must unlock it.
    shot K0 > /dev/null
    gs busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Lock ao 1 /org/freedesktop/secrets/collection/login > /dev/null
    gs sh -c 'setsid timeout 60 secret-tool lookup service vmtest login again < /dev/null > /tmp/keyring-lookup.txt 2>&1 &'
    sleep 6
    shot K1-unlock-prompt > /dev/null
    if gt "$(changed K0 K1-unlock-prompt 300 100 980 330)" 0.2; then
        ok "[keyring] a locked keyring asks for its password"
        ctl type "$PASS"
        ctl key ret
        sleep 3
        check "[keyring] the password typed in the prompt unlocks it" test "$(g cat /tmp/keyring-lookup.txt)" = s3cret-again
    else
        fail "[keyring] no unlock prompt for the locked keyring"
        gs busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock ao 1 /org/freedesktop/secrets/collection/login > /dev/null
    fi
}

crit_panel() {
    say "== panel applets: each opens and closes, one action in some (Fedora: default panel functionality) [$(elapsed)]"
    local t x name box v0 v1
    # On the empty workspace 2, with nothing open (a click on the desktop
    # closes any popup), so the screenshots before and after compare.
    ctl key meta_l-2
    sleep 2
    ctl click 640 400
    sleep 1
    shot N0 > /dev/null
    for t in 639:clock 981:keyboard-layout 1015:accessibility 1055:tiling 1089:sound \
             1124:bluetooth 1158:network 1191:battery 1226:notifications; do
        x=${t%%:*} name=${t#*:}
        ctl click "$x" 15
        sleep 2
        shot "N-$name" > /dev/null
        box=$(ctl bbox "$OUT/N0.ppm" "$OUT/N-$name.ppm" 0 33 1280 720)
        if [ "$box" = none ]; then fail "[panel] the $name applet shows no popup"; continue; fi
        ok "[panel] the $name applet opens ($box)"
        case $name in
            clock)
                ctl click 784 80          # the calendar's next-month arrow
                sleep 1
                shot N-clock-next > /dev/null
                check "[panel] the calendar goes to the next month" gt "$(changed "N-$name" N-clock-next 460 40 820 420)" 0.05 ;;
            sound)
                v0=$(vol | awk '{ print $2 }')
                ctl click 1089 71         # the middle of the output slider (0 to 150%)
                sleep 1
                v1=$(vol | awk '{ print $2 }')
                if [ -n "$v1" ] && gt "$v1" 0.6 && lt "$v1" 0.9; then ok "[panel] the volume slider sets the volume ($v0 -> $v1)"; else fail "[panel] the volume slider did not set the volume ($v0 -> $v1)"; fi ;;
        esac
        ctl click "$x" 15
        sleep 2
        shot "N-$name-closed" > /dev/null
        check "[panel] clicking the $name icon again closes it" lt "$(changed N0 "N-$name-closed")" 0.01
        if [ "$name" = sound ]; then
            gs wpctl set-volume @DEFAULT_AUDIO_SINK@ "${v0:-0.4}"     # back (shows the volume popup)
            sleep 4
        fi
    done
    ctl click 639 15
    sleep 2
    ctl key esc
    sleep 1
    shot N-esc > /dev/null
    if lt "$(changed N0 N-esc)" 0.01; then
        ok "[panel] Escape closes an applet's popup"
    else
        known_issue "[panel] Escape does not close an applet's popup (clicking its icon or elsewhere does; not confirmed upstream)"
        ctl click 639 15
        sleep 2
    fi
    ctl key meta_l-1
    sleep 2
}

# xkb_layout LAYOUT: what the Keyboard page of Settings writes.
xkb_layout() {
    g sh -c "mkdir -p ~/.config/cosmic/com.system76.CosmicComp/v1 && printf '%s' '(
    rules: \"\",
    model: \"\",
    layout: \"$1\",
    variant: \"\",
    options: None,
    repeat_delay: 600,
    repeat_rate: 25,
)' > ~/.config/cosmic/com.system76.CosmicComp/v1/xkb_config"
}

crit_layout() {
    say "== keyboard layout: German (openSUSE: keyboard layout) [$(elapsed)]"
    shot Y0 > /dev/null
    ctl key meta_l-t
    sleep 3
    ctl type "cat > /tmp/layout.txt"
    ctl key ret
    sleep 1
    xkb_layout de
    sleep 3
    shot Y1-layout-de > /dev/null
    # The same keys as "zy" on a US keyboard; letters only, symbols move.
    ctl type "zy"
    ctl key ret ctrl-d
    sleep 1
    check "[layout] with the German layout the keys Z and Y type y and z" test "$(g cat /tmp/layout.txt)" = yz
    check "[layout] the panel shows the layout" gt "$(changed Y0 Y1-layout-de 960 0 1000 30)" 0.05

    # The lock screen types with the same layout (openSUSE keyboard_layout_gdm):
    # for a while the password has a "y", which is the Z key in German. The
    # keyring keeps the old password, so gkr-pam logs that it was invalid.
    local start
    start=$(g date +%s)
    g sudo sh -c 'echo tester:cosmictesty1 | chpasswd'
    shot Y2 > /dev/null
    ctl key meta_l-esc
    sleep 3
    shot Y3-locked > /dev/null
    check "[layout] Super+Escape locks the screen" gt "$(changed Y2 Y3-locked)" 0.2
    unlock Y4-unlocked cosmictestz1
    if lt "$(changed Y2 Y4-unlocked)" 0.01; then
        ok "[layout] the lock screen uses the German layout: the password typed with it unlocks"
        g sudo sh -c "echo tester:$PASS | chpasswd"
    else
        fail "[layout] the password typed with the German layout did not unlock the lock screen"
        g sudo sh -c "echo tester:$PASS | chpasswd"
        ctl type "$PASS"
        ctl key ret
        sleep 5
    fi
    add_window "$start" "$(( $(g date +%s) + 2 ))"
    xkb_layout us
    sleep 3
    ctl type "exit"
    ctl key ret
    sleep 2
}

# openSUSE toolkits: SDL clients. SDL 2 and 3's own test programs (Debian's
# libsdl2-tests, libsdl3-tests), each through Wayland and through X11: a
# window that keeps drawing (testsprite) and keys that reach the program
# (checkkeys). Installed for the test, purged after.
crit_sdl() {
    say "== SDL 2 and SDL 3 programs on Wayland and X11 (openSUSE: toolkits) [$(elapsed)]"
    local d v drv dir prog env
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends libsdl2-tests libsdl3-tests > /dev/null 2>&1; then
        fail "[toolkit] could not install libsdl2-tests and libsdl3-tests"
        return
    fi
    d=$(g sh -c 'tr "\0" "\n" < /proc/$(pgrep -u tester -x cosmic-panel)/environ | sed -n "s/^DISPLAY=//p"')
    for v in 3 2; do
        dir=/usr/libexec/installed-tests/SDL$v
        prog=$dir/testsprite; [ $v = 2 ] && prog=$dir/testsprite2
        for drv in wayland x11; do
            env="DISPLAY=${d:-:1} SDL_VIDEODRIVER=$drv SDL_VIDEO_DRIVER=$drv"
            ctl click 1000 600; sleep 1
            shot SD0 > /dev/null
            gs sh -c "env $env setsid $prog < /dev/null > /tmp/sdl-$v-$drv.log 2>&1 &"
            sleep 5
            shot "SD-$v-$drv-1" > /dev/null
            sleep 1
            shot "SD-$v-$drv-2" > /dev/null
            if gt "$(changed SD0 "SD-$v-$drv-1")" 0.1 && gt "$(changed "SD-$v-$drv-1" "SD-$v-$drv-2")" 0.01; then
                ok "[toolkit] SDL $v ($drv): a window that keeps drawing (testsprite)"
            elif [ $v = 2 ] && [ $drv = wayland ] && g pgrep -f "$prog" > /dev/null; then
                # It runs but no window shows; without libdecor (the decoration
                # library SDL 2 prefers on Wayland) it does.
                g pkill -9 -f "$prog"; sleep 2
                gs sh -c "env $env SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0 setsid $prog < /dev/null > /dev/null 2>&1 &"
                sleep 5
                shot SD-2-wayland-nolibdecor > /dev/null
                if gt "$(changed SD0 SD-2-wayland-nolibdecor)" 0.1; then
                    known_issue "[toolkit] SDL 2 on Wayland shows no window while libdecor (GTK plugin) is installed; with SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0 it does (SDL 2 picks X11 unless told otherwise; not confirmed upstream, cf. pop-os/cosmic-comp#2565)"
                else
                    fail "[toolkit] SDL 2 (wayland): no window, with or without libdecor"
                fi
            else
                fail "[toolkit] SDL $v ($drv): no window that keeps drawing ($(g tail -n 1 /tmp/sdl-$v-$drv.log))"
            fi
            # (SIGKILL: a program that is stuck without a window never reads
            # the quit event SIGTERM becomes, and SDL keeps the screen from
            # going idle while it runs.)
            g pkill -9 -f "$prog"; sleep 2
            # Keys: checkkeys logs "Key pressed ... = Q".
            gs sh -c "env $env SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0 setsid $dir/checkkeys < /dev/null > /tmp/sdl-keys-$v-$drv.log 2>&1 &"
            sleep 4
            ctl type "q"
            sleep 1
            g pkill -9 -f "$dir/checkkeys"; sleep 1
            check "[toolkit] SDL $v ($drv): a key pressed reaches the program (checkkeys)" g grep -q "Key pressed.*= Q" "/tmp/sdl-keys-$v-$drv.log"
        done
    done
    g sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --autoremove libsdl2-tests libsdl3-tests > /dev/null 2>&1
    check "[toolkit] no SDL test program is left running" test -z "$(g pgrep -f /usr/libexec/installed-tests/SDL)"
}

crit_toolkits() {
    say "== Qt 5 and Qt 6 programs (openSUSE: toolkits) [$(elapsed)]"
    local a
    # Started with the launcher's ":" (a command, in the session's own
    # environment); a search for "qt6 settings" lists Qt5 Settings first.
    for a in "qt5ct:qt5ct" "qt6ct:qt6ct"; do
        if ! g test -x "/usr/bin/${a%%:*}"; then
            say "  ${a%%:*} not installed (newer builds of the package recommend it): not tried"
            continue
        fi
        shot T0 > /dev/null
        if launch_app ":${a%%:*}" "${a#*:}"; then
            shot "T-${a#*:}" > /dev/null
            if gt "$(changed T0 "T-${a#*:}")" 0.05; then ok "[toolkit] ${a#*:} shows a window"; else fail "[toolkit] ${a#*:} runs, but no window"; fi
            ctl key meta_l-q
            wait_gone 10 "${a#*:} closed" pgrep -u tester -x "${a#*:}" || fail "[toolkit] Super+Q did not close ${a#*:}"
        else
            fail "[toolkit] ${a#*:} did not start from the launcher"
        fi
    done
    say "== GTK 3 and GTK 4 programs (openSUSE: toolkits) [$(elapsed)]"
    # GTK 4: a zenity message (a test tool); Enter presses its OK.
    shot T0 > /dev/null
    if g test -x /usr/bin/zenity && launch_app ":zenity --info --text=gtk4" zenity; then
        shot T-zenity > /dev/null
        if gt "$(changed T0 T-zenity)" 0.02; then ok "[toolkit] a GTK 4 program shows a window (zenity)"; else fail "[toolkit] zenity runs, but no window"; fi
        ctl key ret
        wait_gone 10 "zenity closed" pgrep -u tester -x zenity || fail "[toolkit] Enter did not close the zenity window"
    else
        fail "[toolkit] zenity (GTK 4) did not start"
    fi
    # GTK 3: Print Settings (system-config-printer, recommended), from the launcher.
    if g test -x /usr/bin/system-config-printer; then
        shot T0 > /dev/null
        ctl key meta_l
        sleep 2
        ctl type "print settings"
        sleep 2
        ctl key ret
        if wait_for 20 "system-config-printer running" pgrep -u tester -f "system-config-printer\.py"; then
            sleep 4
            shot T-printers > /dev/null
            if gt "$(changed T0 T-printers)" 0.05; then ok "[toolkit] a GTK 3 program shows a window (Print Settings)"; else fail "[toolkit] Print Settings runs, but no window"; fi
            ctl key meta_l-q
            wait_gone 10 "Print Settings closed" pgrep -u tester -f "system-config-printer\.py" || fail "[toolkit] Super+Q did not close Print Settings"
        else
            fail "[toolkit] Print Settings (GTK 3) did not start from the launcher"
        fi
    fi
}

# autostart_setup / autostart_check: an entry in ~/.config/autostart runs at
# the next login (openSUSE: application_starts_on_login).
autostart_setup() {
    g sh -c 'mkdir -p ~/.config/autostart && rm -f /tmp/autostart-ran && printf "%s\n" "[Desktop Entry]" "Type=Application" "Name=VM test autostart" "Exec=sh -c \"date +%%s > /tmp/autostart-ran\"" > ~/.config/autostart/vmtest.desktop'
}
autostart_check() {
    if g test -s /tmp/autostart-ran; then
        ok "[autostart] an entry in ~/.config/autostart ran at login"
    else
        fail "[autostart] the entry in ~/.config/autostart did not run at login"
    fi
}

# settings_page PAGE NAME: Settings opened on a page; WX WY = its window.
settings_page() {
    gs sh -c "setsid cosmic-settings $1 < /dev/null > /dev/null 2>&1 &"
    sleep 6
    win "$2"
}

crit_settings() {
    say "== Settings: wallpaper, 24-hour time, default terminal (cosmic-settings TESTING.md) [$(elapsed)]"
    local bg=/home/tester/.config/cosmic/com.system76.CosmicBackground/v1/all
    local actions=/home/tester/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions

    # Wallpaper: a click on another picture changes the background at once,
    # and it stays after leaving the page.
    local orig new new_name
    # On the empty workspace 2, so only the background shows beside the window.
    ctl key meta_l-2
    sleep 2
    orig=$(g grep -o 'source: Path("[^"]*")' "$bg")
    settings_page wallpaper SW0
    ctl scroll $((WX + 659)) $((WY + 385)) down 10
    sleep 2
    shot SW1 > /dev/null
    wclick 659 451                       # a picture in the middle of the grid
    sleep 3
    new=$(g grep -o 'source: Path("[^"]*")' "$bg")
    if [ "$new" = "$orig" ]; then        # that was the current one: the next
        wclick 489 451
        sleep 3
        new=$(g grep -o 'source: Path("[^"]*")' "$bg")
    fi
    shot SW2 > /dev/null
    if gt "$(changed SW1 SW2 0 40 200 700)" 0.5 && [ "$new" != "$orig" ]; then
        new_name=${new##*/}
        ok "[settings-wallpaper] a click on another wallpaper changes the background at once (${new_name%\")})"
    else
        fail "[settings-wallpaper] the background did not change ($new)"
    fi
    ctl key meta_l-q
    sleep 3
    shot SW3 > /dev/null
    if lt "$(changed SW2 SW3 0 40 200 700)" 0.01 && [ "$(g grep -o 'source: Path("[^"]*")' "$bg")" = "$new" ]; then
        ok "[settings-wallpaper] it stays after leaving the page"
    else
        fail "[settings-wallpaper] it did not stay after leaving the page"
    fi
    # Back to the wallpaper from before (through the file the page writes).
    [ -n "$orig" ] && [ "$new" != "$orig" ] && g sed -i "s#${new//#/\\#}#${orig//#/\\#}#" "$bg"
    sleep 3

    # 24-hour time: the panel and the lock screen follow the switch.
    settings_page date-time SD0
    wclick 766 416                       # 24-hour time
    sleep 3
    shot SD1 > /dev/null
    if gt "$(changed SD0 SD1 540 0 740 30)" 0.05 && g grep -q true /home/tester/.config/cosmic/com.system76.CosmicAppletTime/v1/military_time; then
        ok "[settings-time] 24-hour time changes the panel clock"
    else
        fail "[settings-time] the panel clock did not change to 24-hour time"
    fi
    ctl key meta_l-esc
    sleep 4
    shot SD2-lock-24h > /dev/null
    unlock SD2-unlocked
    wclick 766 416                       # back to 12-hour time
    sleep 2
    ctl key meta_l-esc
    sleep 4
    shot SD3-lock-12h > /dev/null
    unlock SD3-unlocked
    check "[settings-time] the lock screen clock follows the setting" gt "$(changed SD2-lock-24h SD3-lock-12h 270 220 670 330)" 0.05
    ctl key meta_l-q
    sleep 2

    # Default terminal: Super+T opens the one chosen.
    if ! g test -x /usr/bin/zutty; then
        say "  no second terminal installed: the default terminal is not tried"
        ctl key meta_l-1
        sleep 2
        return
    fi
    settings_page default-apps SA0
    ctl scroll $((WX + 569)) $((WY + 335)) down 10
    sleep 2
    wclick 779 363                       # the Terminal list
    sleep 2
    wclick 666 439                       # Zutty
    sleep 2
    ctl key meta_l-t
    if wait_for 15 "zutty running" pgrep -u tester -x zutty; then
        ok "[settings-apps] Super+T opens the terminal chosen as default (Zutty)"
        sleep 2
        ctl key meta_l-q
        sleep 2
    else
        fail "[settings-apps] Super+T did not open the terminal chosen as default ($(g grep Terminal "$actions"))"
    fi
    wclick 779 363
    sleep 2
    wclick 707 403                       # COSMIC Terminal, first in the list
    sleep 2
    g grep -q zutty "$actions" && fail "[settings-apps] the default terminal did not go back to COSMIC Terminal"
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# Appearance page: accent colour, light and dark (cosmic-settings TESTING.md).
crit_appearance() {
    say "== Settings, Appearance: accent colour, light and dark from the page [$(elapsed)]"
    local theme=/home/tester/.config/cosmic/com.system76.CosmicTheme
    ctl key meta_l-2
    sleep 2
    settings_page appearance AP0
    wclick 698 431                       # orange, sixth swatch
    sleep 3
    shot AP1-orange > /dev/null
    # winbox finds windows by the default (cyan) accent border.
    if g grep -q '#FFAD00' "$theme.Dark/v2/accent" && [ "$(box_of AP1-orange)" = none ]; then
        ok "[settings-appearance] a new accent colour reaches the window border at once"
    else
        fail "[settings-appearance] the accent colour did not change ($(g grep -m 1 base "$theme.Dark/v2/accent"))"
    fi
    wclick 378 431                       # the default, first swatch
    sleep 3
    shot AP2 > /dev/null
    check "[settings-appearance] the default accent colour comes back" test "$(box_of AP2)" != none
    wclick 684 225                       # Light
    sleep 4
    shot AP3-light > /dev/null
    if g grep -q false "$theme.Mode/v1/is_dark" && gt "$(changed AP2 AP3-light 0 0 1280 32)" 0.5; then
        ok "[settings-appearance] Light on the page turns the panel light"
    else
        fail "[settings-appearance] Light on the page did not change the panel"
    fi
    wclick 462 225                       # Dark
    sleep 4
    shot AP4 > /dev/null
    check "[settings-appearance] Dark brings everything back" lt "$(changed AP2 AP4)" 0.01
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# Settings, Sound: Amplification (the volume slider's end is 150% with it,
# 100% without), and an application's own volume (Sound > Applications, with
# a tone playing) changes that stream, not the device.
crit_sound_settings() {
    say "== Settings, Sound: amplification, an application's own volume [$(elapsed)]"
    local v0 a b s0 s1
    v0=$(gs pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n 1)
    settings_page sound SN0
    wclick 775 164; sleep 2                  # the end of the output volume slider
    a=$(gs pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n 1 | tr -d %)
    wclick 766 315; sleep 2                  # Amplification: off
    wclick 775 164; sleep 2
    b=$(gs pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n 1 | tr -d %)
    wclick 766 315; sleep 2                  # Amplification: on again
    if [ "${a:-0}" -ge 140 ] && [ "${b:-0}" -le 100 ] && [ "${b:-0}" -ge 90 ]; then
        ok "[sound] Amplification: the slider goes to ${a}% with it, ${b}% without"
    else
        fail "[sound] Amplification: the slider's end gave ${a:-?}% with it, ${b:-?}% without"
    fi
    gs pactl set-sink-volume @DEFAULT_SINK@ "$v0"
    g python3 -c '
import math, struct, wave
w = wave.open("/tmp/long.wav", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
w.writeframes(b"".join(struct.pack("<h", int(3000 * math.sin(2 * math.pi * 330 * i / 44100))) for i in range(44100 * 40)))'
    gs sh -c 'setsid paplay --volume=65536 /tmp/long.wav < /dev/null > /dev/null 2>&1 &'
    sleep 2
    ctl scroll $((WX + 572)) $((WY + 335)) down 5; sleep 1
    wclick 572 341; sleep 3                  # Applications
    shot SN1-apps > /dev/null
    # paplay's own stream (others may be listed too, speech-dispatcher's).
    paplay_volume() { gs pactl list sink-inputs | awk '/^Sink Input/ { v = "" } /^[[:space:]]*Volume:/ { v = $5 } /application.name = "paplay"/ { print v; exit }'; }
    s0=$(paplay_volume)
    wclick 489 192; sleep 2                  # the stream's slider (paplay, listed first), near its left end
    s1=$(paplay_volume)
    if [ -n "$s0" ] && [ "${s1%\%}" -lt "${s0%\%}" ] && [ "$(gs pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n 1)" = "$v0" ]; then
        ok "[sound] Sound > Applications lists the playing stream; its slider sets that stream's volume ($s0 -> $s1), not the device's"
    else
        fail "[sound] the application's slider: stream ${s0:-none} -> ${s1:-none}, device $(gs pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n 1) (was $v0)"
    fi
    g pkill -u tester -x paplay
    ctl key meta_l-q
    sleep 2
}

# calendar_shot NAME: open the panel clock's calendar, screenshot NAME, close
# it (a click outside it); false if the popup did not show. (A click on the
# clock is sometimes not taken, and the popup sometimes takes longer: look
# twice, then click again.)
calendar_shot() {
    local i shown=1
    # (Outside the popup: Escape does not close applet popups, a known issue.)
    ctl click 1000 600; sleep 1
    shot "$1-before" > /dev/null
    for i in 1 2 3; do
        ctl click 640 15
        sleep 2; shot "$1" > /dev/null
        gt "$(changed "$1-before" "$1" 460 40 820 480)" 0.3 && { shown=0; break; }
        sleep 2; shot "$1" > /dev/null
        gt "$(changed "$1-before" "$1" 460 40 820 480)" 0.3 && { shown=0; break; }
    done
    ctl click 1000 600; sleep 1
    return $shown
}

# Settings, Date & time: the panel clock's seconds, date and day of week (the
# applet's settings), the first day of the week (the calendar's columns). The
# clock applet's settings are backed up and put back.
crit_datetime() {
    say "== Settings, Date & time: seconds, date, day of week in the panel; first day of the week in the calendar [$(elapsed)]"
    local a b
    cfg_save com.system76.CosmicAppletTime
    ctl key meta_l-2
    sleep 2
    local cal=1
    calendar_shot DT0-calendar && cal=0      # (Sunday first)
    settings_page date-time DT1
    ctl scroll $((WX + 572)) $((WY + 335)) down 10; sleep 1
    shot DT2-clock > /dev/null
    sleep 1.3
    shot DT3-clock > /dev/null
    a=$(changed DT2-clock DT3-clock 500 0 780 32)
    wclick 572 413; sleep 3                  # Date & time applet settings
    wclick 782 252; sleep 2                  # Seconds: on
    shot DT4-seconds > /dev/null
    sleep 1.3
    shot DT5-seconds > /dev/null
    b=$(changed DT4-seconds DT5-seconds 500 0 780 32)
    if lt "$a" 0.001 && gt "$b" 0.003; then
        ok "[settings-time] Seconds on: the panel clock shows them ticking"
    else
        fail "[settings-time] Seconds: the clock changed $a in 1.3 s before, $b with seconds on"
    fi
    wclick 782 252; sleep 2                  # Seconds: off
    shot DT6 > /dev/null
    wclick 782 154; sleep 2                  # Date: off
    shot DT7-no-date > /dev/null
    check "[settings-time] Date off takes the date out of the panel clock" gt "$(changed DT6 DT7-no-date 500 0 780 32)" 0.02
    wclick 782 154; sleep 2                  # Date: on
    wclick 782 203; sleep 2                  # Day of week: on
    shot DT8-weekday > /dev/null
    check "[settings-time] Day of week on adds it to the panel clock" gt "$(changed DT6 DT8-weekday 500 0 780 32)" 0.02
    wclick 782 203; sleep 2                  # Day of week: off
    wclick 785 90; sleep 2                   # Close (applet settings)
    wclick 746 364; sleep 2                  # First day of week
    wclick 741 511; sleep 2                  # Monday
    ctl key meta_l-q; sleep 2
    calendar_shot DT9-calendar-monday || cal=1
    if [ $cal = 1 ]; then
        fail "[settings-time] the panel clock's calendar did not open (DT0-calendar.png, DT9-calendar-monday.png)"
    elif gt "$(changed DT0-calendar DT9-calendar-monday 460 100 820 410)" 0.015; then
        ok "[settings-time] First day of week Monday: the calendar's columns start with Monday"
    else
        fail "[settings-time] First day of week did not change the calendar (DT9-calendar-monday.png)"
    fi
    # Back to Sunday in Settings (the clock applet keeps a value whose file
    # is removed, so the restore below alone would leave Monday).
    settings_page date-time DT10
    ctl scroll $((WX + 572)) $((WY + 335)) down 10; sleep 1
    wclick 746 364; sleep 2                  # First day of week
    wclick 739 476; sleep 2                  # Sunday
    ctl key meta_l-q; sleep 2
    calendar_shot DT11-calendar-sunday
    check "[settings-time] First day of week Sunday again: the calendar as before" lt "$(changed DT0-calendar DT11-calendar-sunday 460 100 820 410)" 0.01
    cfg_restore com.system76.CosmicAppletTime
    sleep 3
    ctl key meta_l-1
    sleep 2
}

# Settings, Appearance: style (roundness) and interface density; Settings,
# Dock: auto-hide (with a maximized and with a tiled window), position on
# screen, extend to the screen edges. The dock's settings are backed up and
# put back (the panel takes them up at once).
crit_style_dock() {
    say "== Settings: roundness, interface density, the dock's auto-hide, position and style [$(elapsed)]"
    local dock=/home/tester/.config/cosmic/com.system76.CosmicPanel.Dock start
    ctl key meta_l-2
    sleep 2
    ctl click 640 400
    sleep 1
    shot SY0-desktop > /dev/null
    settings_page appearance SY1
    ctl scroll $((WX + 572)) $((WY + 335)) down 10; sleep 1
    shot SY2-round > /dev/null
    wclick 720 358; sleep 3                  # Style: Square
    shot SY3-square > /dev/null
    check "[settings-appearance] Square makes the window corners square" gt "$(changed SY2-round SY3-square "$WX" "$WY" $((WX + 20)) $((WY + 20)))" 0.1
    ctl scroll $((WX + 572)) $((WY + 335)) down 5; sleep 1
    shot SY4-comfortable > /dev/null
    wclick 363 271; sleep 3                  # Interface density: Compact
    shot SY5-compact > /dev/null
    if g grep -q Compact /home/tester/.config/cosmic/com.system76.CosmicTk/v1/interface_density &&
       gt "$(changed SY4-comfortable SY5-compact "$WX" "$WY" $((WX + 858)) $((WY + 465)))" 0.1; then
        ok "[settings-appearance] Compact density makes the window denser"
    else
        fail "[settings-appearance] Compact density changed nothing (SY5-compact.png)"
    fi
    # Comfortable (where it is in the compact layout). The first click after
    # the density changed is sometimes lost (the page is laid out anew): up to
    # three, until the setting says so.
    local i
    for i in 1 2 3; do
        wclick 347 175; sleep 3
        g grep -q Standard /home/tester/.config/cosmic/com.system76.CosmicTk/v1/interface_density && break
    done
    shot SY6-comfortable > /dev/null
    check "[settings-appearance] Comfortable brings the density back" lt "$(changed SY4-comfortable SY6-comfortable "$WX" "$WY" $((WX + 858)) $((WY + 465)))" 0.01
    ctl scroll $((WX + 572)) $((WY + 335)) up 5; sleep 1
    wclick 424 358; sleep 3                  # Style: Round
    shot SY7-round > /dev/null
    check "[settings-appearance] Round brings the round corners back" lt "$(changed SY2-round SY7-round "$WX" "$WY" $((WX + 20)) $((WY + 20)))" 0.01
    ctl key meta_l-q
    sleep 2

    # The panel restarts the dock's applets for each change (exit code 137),
    # and reads its settings while they are written back: a closing window.
    start=$(g date +%s)
    cfg_save com.system76.CosmicPanel.Dock
    settings_page dock SY8
    wclick 766 290; sleep 2                  # Automatically hide dock: on
    ctl key meta_l-m; sleep 3                # maximized: the positions below are fixed
    ctl move 640 400; sleep 3
    shot SY9-hidden > /dev/null
    ctl move 640 799; sleep 3                # the pointer at the bottom edge
    shot SY10-shown > /dev/null
    check "[dock] auto-hide: hidden behind a maximized window, shown at the bottom edge" gt "$(changed SY9-hidden SY10-shown 300 720 980 800)" 0.3
    ctl move 640 400; sleep 1
    ctl key meta_l-m; sleep 2                # not maximized; tiled instead
    ctl key meta_l-y; sleep 3
    ctl move 640 400; sleep 3
    shot SY11-tiled > /dev/null
    check "[dock] auto-hide: hidden behind a tiled window" gt "$(changed SY11-tiled SY10-shown 300 720 980 800)" 0.3
    ctl key meta_l-y; sleep 2
    win SY11b
    wclick 766 290; sleep 2                  # auto-hide off
    ctl key meta_l-m; sleep 3
    shot SY12-bottom > /dev/null
    ctl click 1117 369; sleep 1              # Position on screen
    ctl click 1095 409; sleep 4              # Left
    shot SY13-left > /dev/null
    if g grep -q Left "$dock/v1/anchor" && gt "$(changed SY12-bottom SY13-left 0 100 100 700)" 0.3; then
        ok "[dock] Position Left moves the dock to the left edge"
    else
        fail "[dock] Position Left did not move the dock (SY13-left.png)"
    fi
    ctl key meta_l-m; sleep 3
    shot SY14-left-normal > /dev/null
    ctl key meta_l-m; sleep 3
    ctl click 1171 569; sleep 3              # Extend dock to screen edges (the dock on the left moves the window)
    ctl key meta_l-m; sleep 3
    shot SY15-extended > /dev/null
    check "[dock] Extend dock to screen edges makes it run the whole edge" gt "$(changed SY14-left-normal SY15-extended 0 40 90 800)" 0.1
    ctl key meta_l-q
    sleep 2
    cfg_restore com.system76.CosmicPanel.Dock
    sleep 4
    ctl click 640 400
    sleep 1
    shot SY16-dock-back > /dev/null
    check "[dock] with its settings put back the dock is at the bottom again" lt "$(changed SY0-desktop SY16-dock-back 0 40 1280 800)" 0.01
    add_window "$start" "$(g date +%s)"
    ctl key meta_l-1
    sleep 2
}

# About page: the device name (the hostname).
crit_about() {
    say "== Settings, About: rename the device [$(elapsed)]"
    local host
    host=$(g hostnamectl --static)
    ctl key meta_l-2
    sleep 2
    settings_page about AB0
    wclick 580 220                       # the pencil beside the name
    sleep 1
    ctl key ctrl-a
    ctl type renamed-vm
    ctl key ret                          # only Enter saves (pop-os/cosmic-settings#1047)
    sleep 4
    shot AB1 > /dev/null
    if [ "$(g hostnamectl --static)" = renamed-vm ]; then
        ok "[settings-about] the new device name is the hostname"
        g sudo hostnamectl set-hostname "$host"
    elif g busctl call org.freedesktop.hostname1 /org/freedesktop/hostname1 org.freedesktop.hostname1 \
             SetStaticHostname sb renamed-vm false 2>&1 | grep -q "Interactive authentication required"; then
        known_issue "[settings-about] renaming the device does nothing: Settings asks hostnamed without allowing a password prompt (SetStaticHostname, interactive false) and Debian's polkit wants an admin password; no prompt, no error, the old name comes back"
    else
        fail "[settings-about] the device name did not change the hostname"
    fi
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# Suspend from the panel's power menu, wake, unlock (Fedora: suspend and
# resume). QEMU suspends the VM to S3 and wakes it with system_wakeup; the
# display survives because virtio-vga sits on a PCIe port with
# x-pcie-pm-no-soft-reset (vm-session.sh).
crit_suspend() {
    say "== suspend from the panel's power menu, wake, unlock (Fedora: suspend and resume) [$(elapsed)]"
    local start comp boot state= snd v0 v1
    comp=$(g pgrep -u tester -x cosmic-comp)
    snd=$(gs pactl get-default-sink 2>&1)
    boot=$(g cat /proc/sys/kernel/random/boot_id)
    shot SP0 > /dev/null
    start=$(g date +%s)
    ctl click 1259 15                    # the power icon
    sleep 2
    ctl click 988 233                    # Suspend, the moon
    for _ in $(seq 15); do
        state=$(ctl status)
        [ "$state" = suspended ] && break
        sleep 2
    done
    if [ "$state" != suspended ]; then
        fail "[suspend] Suspend in the power menu did not suspend the machine (QEMU: $state)"
        ctl key esc
        ctl click 640 400
        return
    fi
    ok "[suspend] Suspend in the power menu suspends the machine (S3)"
    sleep 5
    ctl wakeup
    sleep 8
    ctl click 640 400                    # input turns the screen on
    sleep 3
    shot SP1-woken 0.9 > /dev/null
    check "[suspend] after waking the screen shows, locked" gt "$(changed SP0 SP1-woken)" 0.2
    unlock SP2-unlocked
    check "[suspend] the password unlocks it, the desktop is as before" lt "$(changed SP0 SP2-unlocked)" 0.01
    if [ "$(g pgrep -u tester -x cosmic-comp)" = "$comp" ] && [ "$(g cat /proc/sys/kernel/random/boot_id)" = "$boot" ]; then
        ok "[suspend] the same session and boot carry on"
    else
        fail "[suspend] the session or the boot did not survive the suspend"
    fi
    # Sound after waking: cosmic-epoch#2580 (a "Dummy Output" after resume),
    # cosmic-settings-daemon#193 (volume keys dead).
    check "[suspend] the sound output is the same after waking ($snd)" test "$(gs pactl get-default-sink 2>&1)" = "$snd"
    v0=$(vol | awk '{ print $2 }')
    ctl key volumeup
    sleep 2
    v1=$(vol | awk '{ print $2 }')
    ctl key volumedown
    sleep 2
    if [ -n "$v1" ] && gt "$v1" "$v0"; then ok "[suspend] the volume keys work after waking ($v0 -> $v1)"; else fail "[suspend] the volume-up key did nothing after waking ($v0 -> $v1)"; fi
    add_window "$start" "$(g date +%s)"
}

# Shut down from the panel's power menu, then Cancel: the dialog counts down
# 60 seconds and then shuts down by itself, so Cancel must stop that.
crit_shutdown_cancel() {
    say "== power menu: Shut down, then Cancel; nothing happens after the countdown [$(elapsed)]"
    local boot
    boot=$(g cat /proc/sys/kernel/random/boot_id)
    shot PD0 > /dev/null
    ctl click 1259 15                    # the power icon
    sleep 2
    ctl click 1211 233                   # Shut down
    sleep 2
    shot PD1-shutdown-dialog > /dev/null
    check "[power] Shut down in the power menu asks first (a dialog with a countdown)" gt "$(changed PD0 PD1-shutdown-dialog 356 291 924 466)" 0.3
    ctl click 631 426                    # Cancel
    sleep 2
    shot PD2 > /dev/null
    check "[power] Cancel closes the dialog" lt "$(changed PD0 PD2)" 0.01
    sleep 62
    if [ "$(g cat /proc/sys/kernel/random/boot_id 2>/dev/null)" = "$boot" ] && g pgrep -u tester -x cosmic-panel > /dev/null; then
        ok "[power] after Cancel the countdown does not shut down"
    else
        fail "[power] the machine went down after Cancel"
    fi
}

crit_idle() {
    say "== idle: the screen turns off and the session locks (screen lock on idle) [$(elapsed)]"
    local f=/home/tester/.config/cosmic/com.system76.CosmicIdle/v1/screen_off_time
    shot I0 > /dev/null
    # What Settings' Power page writes, in milliseconds: 15 seconds.
    g sh -c "printf %s 'Some(15000)' > $f"
    sleep 25
    shot I1-screen-off > /dev/null
    check "[idle] after 15 s without input the screen turns off" gt "$(tail -n 1 "$REPORT" | grep -o 'top=[0-9.]*' | cut -d= -f2)" 0.98
    # Back to 15 minutes before anything else (removing the file does not
    # reset the running service).
    g sh -c "printf %s 'Some(900000)' > $f"
    ctl click 640 400                    # input wakes the screen
    sleep 3
    shot I2-woken > /dev/null
    check "[idle] input turns it on again, locked" gt "$(changed I0 I2-woken)" 0.2
    if [ "$(g loginctl show-session "$(session_id)" -p LockedHint --value)" != yes ]; then
        known_issue "[idle] logind's LockedHint stays \"no\" while the screen is locked (also with Super+Escape): programs that ask logind cannot tell; not confirmed upstream"
    fi
    unlock I3-unlocked
    check "[idle] the password unlocks it, the desktop is as before" lt "$(changed I0 I3-unlocked)" 0.01
}

# relogin: log out with the dialog and log in again (errors while the session
# closes are in a known window, as for the other log outs).
relogin() {
    local start
    start=$(g date +%s)
    ctl key meta_l-shift-esc
    sleep 2
    ctl key tab
    sleep 1
    ctl key ret
    wait_gone 30 "cosmic-comp gone" pgrep -u tester -x cosmic-comp
    wait_for 60 "login screen back" pgrep -u cosmic-greeter -x cosmic-greeter
    sleep 5
    add_window "$start" "$(g date +%s)"
    log_in
}
panel_lang() { g sh -c 'tr "\0" "\n" < /proc/$(pgrep -u tester -x cosmic-panel)/environ | sed -n "s/^LANG=//p"'; }

# crit_language_setup (before a log out) and crit_language_check (after the
# next log in): German chosen in Settings, as a person would; then German for
# the whole system, as Debian sets it (/etc/default/locale), checked in the
# panel and in Settings.
crit_language_setup() {
    say "== language: German in Settings (Fedora: critical path translations) [$(elapsed)]"
    # Settings lists only the locales the system has; generating one is the
    # administrator's part (what dpkg-reconfigure locales does).
    g sudo sh -c 'sed -i "s/^# *de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/" /etc/locale.gen && locale-gen > /dev/null'
    ctl key meta_l-2
    sleep 2
    settings_page region-language L0-settings-english
    wclick 754 287                       # Add language
    sleep 3
    wclick 636 265                       # German, second in the list
    sleep 2
    wclick 784 90                        # Close
    sleep 2
    wclick 774 288                       # German's menu (second row)
    sleep 2
    wclick 687 327                       # Move up
    sleep 3
    check "[language] Settings puts German first in the preferred languages" \
        test "$(g sh -c 'grep -o "\"[^\"]*\"" ~/.config/cosmic/com.system76.CosmicSettings/v1/system_locales | head -n 1')" = '"de_DE.utf8"'
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
    shot L1-panel-english > /dev/null
}

crit_language_check() {
    if [ "$(panel_lang)" = de_DE.utf8 ] || [ "$(panel_lang)" = de_DE.UTF-8 ]; then
        ok "[language] the session after choosing German in Settings is German"
    else
        known_issue "[language] choosing German in Settings changes nothing on Debian (LANG=$(panel_lang)): Debian's systemd refuses SetLocale, and the per-user AccountsService call fails (Settings sends 'de_DE:de:en_US:en' where one locale is expected); the login screen does not use the AccountsService language either"
    fi
    say "  German for the whole system (/etc/default/locale), log out and in"
    g sudo sh -c 'echo LANG=de_DE.UTF-8 > /etc/default/locale'
    # The login screen takes the system's language at its next start (PAM's
    # pam_env reads /etc/default/locale): its date line in German. (Its
    # "Password:" prompt is PAM's own, through greetd, which stays English.)
    logout_to_greeter tester
    shot L1b-greeter-german > /dev/null
    check "[language] the login screen is German too (the date line; English: 10-logged-out.png)" \
        gt "$(changed 10-logged-out L1b-greeter-german 235 150 640 200)" 0.1
    log_in
    shot L2-panel-german > /dev/null
    check "[language] with LANG=de_DE.UTF-8 the session is German" test "$(panel_lang)" = de_DE.UTF-8
    check "[language] the panel is translated (Applications)" gt "$(changed L1-panel-english L2-panel-german 100 0 260 30)" 0.1
    ctl key meta_l-2
    sleep 2
    settings_page region-language L3-settings-german
    check "[language] Settings is translated" gt "$(changed L0-settings-english L3-settings-german $((WX + 30)) $((WY + 60)) $((WX + 290)) $((WY + 450)))" 0.02
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
    g sudo sh -c 'echo LANG=en_US.UTF-8 > /etc/default/locale'   # English again from the next login
}

# Fedora "critical path translations", GNOME's welcome locales: the first-login
# wizard in German; Arabic (right to left) and Japanese (another script and
# font) in Settings. Programs started with LANG set, in the English session.
crit_translations() {
    say "== translations: the wizard in German; Settings in Arabic (right to left) and Japanese (Fedora: critical path translations) [$(elapsed)]"
    local l a b
    g sudo cp /etc/locale.gen /tmp/vmtest-locale.gen
    g sudo sed -i -E 's/^# *(de_DE|ar_EG|ja_JP)\.UTF-8 UTF-8/\1.UTF-8 UTF-8/' /etc/locale.gen
    g sudo locale-gen > /dev/null 2>&1
    ctl key meta_l-2
    sleep 2
    # The wizard runs once per user ($HOME/.config/cosmic-initial-setup-done):
    # a home of its own for this. Its first page turns the screen reader on.
    for l in en_US de_DE; do
        g sh -c 'rm -rf /tmp/vmtest-wizhome && mkdir /tmp/vmtest-wizhome'
        gs sh -c "env LANG=$l.UTF-8 HOME=/tmp/vmtest-wizhome setsid cosmic-initial-setup < /dev/null > /dev/null 2>&1 &"
        sleep 8
        shot "TR-wizard-$l" > /dev/null
        g pkill -u tester -f '^cosmic-initial-setup'
        sleep 2
    done
    gs busctl --user set-property org.a11y.Bus /org/a11y/bus org.a11y.Status ScreenReaderEnabled b false
    set -- $(ctl winbox "$OUT/TR-wizard-en_US.ppm")
    if [ "$1" = none ]; then
        fail "[translations] the first-login wizard did not show (TR-wizard-en_US.png)"
    else
        check "[translations] the first-login wizard in German (its first page differs from English)" \
            gt "$(changed TR-wizard-en_US TR-wizard-de_DE "$1" "$2" "$3" "$4")" 0.015
    fi
    wait_gone 10 "the screen reader stopped" pgrep -u tester -x orca || g pkill -u tester -x orca
    for l in en_US ar_EG ja_JP; do
        gs sh -c "env LANG=$l.UTF-8 setsid cosmic-settings sound < /dev/null > /dev/null 2>&1 &"
        sleep 7
        win "TR-settings-$l"
        g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
        sleep 2
    done
    check "[translations] Settings in Arabic (the sidebar differs from English)" \
        gt "$(changed TR-settings-en_US TR-settings-ar_EG $((WX + 10)) $((WY + 50)) $((WX + 290)) $((WY + 455)))" 0.02
    # Mirrored, the sidebar (the lighter card) would be on the right.
    a=$(ctl pixel "$OUT/TR-settings-ar_EG.ppm" $((WX + 190)) $((WY + 445)) | cut -d' ' -f1)
    b=$(ctl pixel "$OUT/TR-settings-ar_EG.ppm" $((WX + 590)) $((WY + 445)) | cut -d' ' -f1)
    if [ "${b:-0}" -gt "${a:-0}" ]; then
        ok "[translations] Arabic: the layout is mirrored (right to left)"
    else
        known_issue "[translations] Arabic text is shaped and right to left, but the layout is not mirrored: the sidebar stays on the left (pop-os/cosmic-epoch#888, open)"
    fi
    a=$(g fc-match -f '%{family}' :lang=ja)
    if g sh -c 'fc-list :lang=ja | grep -q .'; then
        check "[translations] Settings in Japanese, drawn with a font that has Japanese ($a)" \
            gt "$(changed TR-settings-en_US TR-settings-ja_JP $((WX + 10)) $((WY + 50)) $((WX + 290)) $((WY + 455)))" 0.02
    else
        known_issue "[translations] no font with Japanese is installed: Japanese text shows as boxes (Debian's Japanese desktop task installs one, e.g. fonts-noto-cjk)"
    fi
    # The locales as before (Settings' language list counts on them).
    g sudo sh -c 'cp /tmp/vmtest-locale.gen /etc/locale.gen && locale-gen > /dev/null 2>&1'
    ctl key meta_l-1
    sleep 2
}

crit_password() {
    say "== Settings: change the password (openSUSE: change_password) [$(elapsed)]"
    local before after new=cosmictest2
    before=$(g sudo getent shadow tester | cut -d: -f2)
    ctl key meta_l-2
    sleep 2
    settings_page users U0
    wclick 782 164                       # open the user's entry
    sleep 2
    wclick 716 347                       # Change password
    sleep 3
    wclick 429 203                       # Password
    ctl type "$new"
    wclick 429 279                       # Confirm password
    ctl type "$new"
    sleep 1
    wclick 658 350                       # Save
    sleep 4
    shot U1-after-save > /dev/null
    after=$(g sudo getent shadow tester | cut -d: -f2)
    if [ "$after" = "$before" ]; then
        known_issue "[password] Change password in Settings does nothing: AccountsService answers \"Authentication is required\" and no password prompt appears; Settings shows no error (the same call with interactive authorization allowed does show COSMIC's admin prompt; Add user fails the same way)"
    else
        ok "[password] Settings changed the password"
        shot U2 > /dev/null
        ctl key meta_l-esc
        sleep 4
        ctl type "$new"
        ctl key ret
        sleep 5
        shot U3-unlocked-new > /dev/null
        check "[password] the lock screen takes the new password" lt "$(changed U2 U3-unlocked-new)" 0.01
        # The old one back (as root), so the keyring and later logins match.
        g sh -c "echo 'tester:$PASS' | sudo chpasswd"
    fi
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
}

# notify SUMMARY MS: a notification, as an application sends it.
notify() {
    gs busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
        org.freedesktop.Notifications Notify 'susssasa{sv}i' vmtest 0 dialog-information \
        "$1" "Sent by the VM session test" 0 0 "$2" > /dev/null
}

crit_notifications() {
    say "== notifications: listed in the applet; Do Not Disturb (Fedora: desktop notifications) [$(elapsed)]"
    local dnd=/home/tester/.config/cosmic/com.system76.CosmicNotifications/v1/do_not_disturb
    ctl key meta_l-2
    sleep 2
    ctl click 640 400                    # nothing open
    sleep 2
    ctl click 1226 15                    # the notifications applet
    sleep 2
    ctl click 1171 124                   # Clear all notifications
    sleep 2
    shot NA0-empty > /dev/null
    ctl click 1226 15
    sleep 2
    shot NA0-closed > /dev/null
    notify "Listed in the applet" 3000
    sleep 2
    shot NA0-popup > /dev/null
    check "[notify] the notification pops up" gt "$(changed NA0-closed NA0-popup 900 30 1280 200)" 0.05
    sleep 5                              # the pop-up has gone
    ctl click 1226 15
    sleep 2
    shot NA1-listed > /dev/null
    check "[notify] the applet lists a notification after its pop-up has gone" gt "$(changed NA0-empty NA1-listed 944 150 1256 245)" 0.1
    ctl click 1231 63                    # Do Not Disturb on
    sleep 1
    check "[notify] the applet switches Do Not Disturb on" g grep -q true "$dnd"
    ctl click 1226 15
    sleep 2
    shot NA2 > /dev/null
    notify "Held back" 5000
    sleep 2
    shot NA3-dnd > /dev/null
    check "[notify] with Do Not Disturb no pop-up shows" lt "$(changed NA2 NA3-dnd 900 30 1280 200)" 0.01
    ctl click 1226 15
    sleep 2
    ctl click 1231 63                    # Do Not Disturb off
    sleep 1
    ctl click 1171 124                   # Clear all notifications
    sleep 1
    ctl click 1226 15
    sleep 2
    notify "Shown again" 3000
    sleep 2
    shot NA4 > /dev/null
    check "[notify] with Do Not Disturb off pop-ups show again" gt "$(changed NA2 NA4 900 30 1280 200)" 0.05
    sleep 5
    ctl key meta_l-1
    sleep 2
}

crit_graphics() {
    say "== 3D on software rendering: OpenGL on Wayland and X11, Vulkan (openSUSE glxgears; Fedora graphics) [$(elapsed)]"
    local t cmd p
    ctl key meta_l-2
    sleep 2
    # COMMAND:PROCESS (the process name as the kernel shortens it)
    for t in "es2gears_wayland:es2gears_waylan" "glxgears:glxgears" "vkcube --wsi wayland:vkcube"; do
        cmd=${t%%:*} p=${t#*:}
        if ! g sh -c "command -v ${cmd%% *}" > /dev/null; then say "  ${cmd%% *} not installed"; continue; fi
        shot G0 > /dev/null
        if launch_app ":$cmd" "$p"; then
            sleep 3
            shot G1 > /dev/null
            sleep 1
            shot G2 > /dev/null
            if gt "$(changed G0 G1)" 0.02 && gt "$(changed G1 G2)" 0.001 && g pgrep -u tester -x "$p" > /dev/null; then
                ok "[graphics] $cmd draws (a window, and it moves)"
            else
                fail "[graphics] $cmd shows no moving picture ($(changed G0 G1), then $(changed G1 G2))"
            fi
            ctl key meta_l-q
            wait_gone 10 "$p closed" pgrep -u tester -x "$p" || { fail "[graphics] Super+Q did not close $cmd"; g pkill -u tester -x "$p"; }
        else
            fail "[graphics] $cmd did not start"
        fi
    done
    ctl key meta_l-1
    sleep 2
}

# logout_to_greeter USER: log USER out with the dialog, back to the login screen.
logout_to_greeter() {
    local start
    start=$(g date +%s)
    ctl key meta_l-shift-esc
    sleep 2
    ctl key tab
    sleep 1
    ctl key ret
    wait_gone 30 "$1's session gone" pgrep -u "$1" -x cosmic-comp
    wait_for 60 "login screen back" pgrep -u cosmic-greeter -x cosmic-greeter
    sleep 6
    add_window "$start" "$(g date +%s)"
}

crit_second_user() {
    say "== a second user: chosen on the login screen, own first-login wizard (Fedora: user switching) [$(elapsed)]"
    local start
    # Settings' Add user fails like Change password (known); an administrator
    # adds one from the command line.
    g sudo sh -c 'useradd -m -s /bin/bash -c "Second User" second && echo second:secondpass1 | chpasswd'
    logout_to_greeter tester
    ctl click 386 413                    # the login screen's user list
    sleep 2
    shot SU1-user-list > /dev/null
    ctl click 348 488                    # Second User (below COSMIC Tester)
    sleep 2
    ctl type secondpass1
    ctl key ret
    if ! wait_for 90 "second user's session" pgrep -u second -x cosmic-panel; then
        fail "[users] the second user could not log in from the login screen's list"
        return
    fi
    ok "[users] the second user, chosen in the login screen's list, logs in"
    if wait_for 30 "wizard for the second user" pgrep -u second -f cosmic-initial-setup; then
        ok "[users] the first-login wizard starts for the second user"
        if wait_for 20 "screen reader (orca) started by the wizard" pgrep -u second -x orca; then
            # cosmic-session stops orca, and ends it if it takes over a
            # second ("Failed to stop program gracefully"): a known window.
            start=$(g date +%s)
            ctl click 908 270
            wait_gone 20 "screen reader stopped" pgrep -u second -x orca
            add_window "$start" "$(( $(g date +%s) + 3 ))"
        fi
        ctl click 925 528; sleep 3                                  # accessibility
        ctl click 925 528; sleep 3                                  # language
        ctl click 500 322; sleep 1                                  # keyboard: English (US)
        ctl click 925 528; sleep 3
        ctl click 636 258; ctl type london; ctl key ret; sleep 4    # timezone (already set)
        start=$(g date +%s)
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            g sudo test -e /home/second/.config/cosmic-initial-setup-done && break
            start=$(g date +%s)
            ctl click 925 528
            sleep 3
        done
        sleep 2
        add_window "$start" "$(( $(g date +%s) + 10 ))"
        check "[users] the second user's wizard finishes" g sudo test -e /home/second/.config/cosmic-initial-setup-done
    else
        fail "[users] no first-login wizard for the second user"
    fi
    shot SU2-second-desktop > /dev/null
    ctl key meta_l-t
    if wait_for 20 "the second user's terminal" pgrep -u second -x cosmic-term; then
        ok "[users] Super+T opens a terminal for the second user"
        sleep 2
        ctl key meta_l-q
        sleep 2
    else
        fail "[users] Super+T did nothing for the second user"
    fi
    logout_to_greeter second
    ctl click 386 413
    sleep 2
    ctl click 355 452                    # COSMIC Tester
    sleep 2
    log_in
    check "[users] back to the first user from the login screen's list" test -n "$(g pgrep -u tester -x cosmic-panel)"
}

# The login screen types with the system's layout, /etc/default/keyboard
# (openSUSE keyboard_layout_gdm), here German as the installer would set it,
# with the user's layout German too. The password has a "y", the Z key in
# German. The package starts the login screen through
# /usr/libexec/cosmic-greeter-debian-start, which gives it that layout;
# builds before it typed US (pop-os/cosmic-greeter#519).
greeter_type_login() {
    wait_for 60 "login screen" pgrep -u cosmic-greeter -x cosmic-greeter > /dev/null
    sleep 8
    ctl type "cosmictestz1"
    ctl key ret
    wait_for 60 "tester's session" pgrep -u tester -x cosmic-panel > /dev/null
}
system_layout() { g sudo sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$1\"/" /etc/default/keyboard; }
crit_greeter_layout() {
    say "== keyboard layout on the login screen: German (openSUSE: keyboard_layout_gdm) [$(elapsed)]"
    local cfg=/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1/xkb_config start
    # From here the password differs from the keyring's: gkr-pam logs it.
    start=$(g date +%s)
    system_layout de
    xkb_layout de
    g sudo sh -c 'echo tester:cosmictesty1 | chpasswd'
    sleep 2
    logout_to_greeter tester             # the login screen starts again
    shot GL0-greeter-de > /dev/null
    if greeter_type_login; then
        ok "[layout] the login screen types with the system's German layout"
    elif g test -x /usr/libexec/cosmic-greeter-debian-start; then
        shot GL1-refused > /dev/null
        fail "[layout] the login screen did not type German, though cosmic-greeter-debian-start set it up ($(g sudo head -c 300 "$cfg" | tr '\n' ' '))"
        g sudo sh -c "echo tester:$PASS | chpasswd"
        ctl key ctrl-a backspace
        log_in
    else
        shot GL1-refused > /dev/null
        known_issue "[layout] the login screen types US whatever the layout: since 1.5.0 the greeter no longer writes its compositor's xkb_config (pop-os/cosmic-greeter#519); builds after 13 set it from /etc/default/keyboard"
        # What newer builds do: the greeter's own xkb_config.
        g sudo -u cosmic-greeter sh -c "mkdir -p \${0%/*} && printf %s '(rules: \"\", model: \"\", layout: \"de\", variant: \"\", options: None, repeat_delay: 600, repeat_rate: 25)' > \$0" "$cfg"
        g sudo systemctl restart display-manager.service
        if greeter_type_login; then
            ok "[layout] with the layout in the greeter's own xkb_config ($cfg) the login screen types German"
        else
            fail "[layout] even with the greeter's own xkb_config the German password was refused"
            g sudo sh -c "echo tester:$PASS | chpasswd"
            log_in
        fi
        g sudo rm -f "$cfg"
    fi
    sleep 10
    g sudo sh -c "echo tester:$PASS | chpasswd"
    system_layout us
    add_window "$start" "$(( $(g date +%s) + 2 ))"
    xkb_layout us
    sleep 2
}

# admin_prompt BEFORE NAME: COSMIC's admin password prompt (cosmic-osd, the
# polkit agent) is on screen, compared with the screenshot BEFORE; answers it.
admin_prompt() {
    sleep 4
    shot "$2" > /dev/null
    gt "$(changed "$1" "$2" 355 253 925 503)" 0.3 || return 1
    ctl type "$PASS"
    ctl key ret
}

# menu_item BEFORE X Y UP NAME: right-click at X,Y and click the item UP
# pixels above the bottom of the context menu that opens (it opens below the
# click or, near the screen's bottom, moved up, so its top varies but its
# items keep their distance from its bottom); NAME is the screenshot.
menu_item() {
    local box
    ctl click "$2" "$3" right
    sleep 2
    shot "$5" > /dev/null
    box=$(ctl bbox "$OUT/$1.ppm" "$OUT/$5.ppm" $(( $2 + 1 )) $(( $3 + 40 )) 1280 800)
    [ "$box" != none ] || return 1
    set -- $2 $3 $4 $box
    ctl click $(( $1 + 60 )) $(( $7 - $3 ))
}

# COSMIC Files' Compress and Extract (Fedora: desktop_app_basic, archive
# manager; COSMIC has no separate archive app).
crit_archive() {
    say "== Files: compress a folder, extract a zip and a tar.gz (Fedora: archive manager) [$(elapsed)]"
    g sh -c 'rm -rf ~/atest && mkdir -p ~/atest/docs && echo hello > ~/atest/docs/a.txt && echo world > ~/atest/docs/b.txt'
    gs sh -c 'setsid cosmic-files /home/tester/atest < /dev/null > /dev/null 2>&1 &'
    wait_for 20 "cosmic-files running" pgrep -u tester -x cosmic-files || { fail "[archive] cosmic-files did not start"; return; }
    sleep 4
    win AR0
    # The only row is at the top of the file list.
    menu_item AR0 $((WX + 394)) $((WY + 117)) 130 AR1-menu || fail "[archive] no context menu on the folder"
    sleep 2
    shot AR2-dialog > /dev/null
    ctl key ret                          # Create: docs.zip
    if wait_for 15 "docs.zip made" test -s atest/docs.zip &&
       [ "$(g python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); print(*sorted(z.namelist()), z.read("docs/a.txt").decode().strip())' atest/docs.zip)" = "docs/ docs/a.txt docs/b.txt hello" ]; then
        ok "[archive] Compress makes a zip of a folder with its files"
    else
        fail "[archive] Compress did not make docs.zip with the folder's files ($(g ls atest | tr '\n' ' '))"
    fi
    # Extract puts the files in a folder named after the archive.
    g rm -rf atest/docs
    sleep 2
    shot AR3 > /dev/null
    menu_item AR3 $((WX + 394)) $((WY + 117)) 202 AR4-menu || fail "[archive] no context menu on docs.zip"
    if wait_for 15 "docs.zip extracted" test -f atest/docs/docs/a.txt && [ "$(g cat atest/docs/docs/b.txt)" = world ]; then
        ok "[archive] Extract unpacks a zip"
    else
        fail "[archive] Extract did not unpack docs.zip ($(g find atest | tr '\n' ' '))"
    fi
    g sh -c 'cd atest && rm -rf docs docs.zip && mkdir src && echo tgz > src/c.txt && tar czf src.tar.gz src && rm -r src'
    sleep 2
    shot AR5 > /dev/null
    menu_item AR5 $((WX + 394)) $((WY + 117)) 202 AR6-menu || fail "[archive] no context menu on src.tar.gz"
    if wait_for 15 "src.tar.gz extracted" test -f atest/src/src/c.txt && [ "$(g cat atest/src/src/c.txt)" = tgz ]; then
        ok "[archive] Extract unpacks a tar.gz"
    else
        fail "[archive] Extract did not unpack src.tar.gz ($(g find atest | tr '\n' ' '))"
    fi
    ctl key meta_l-q
    sleep 2
    g rm -rf atest
}

# Settings' Panel page: add an applet, use it, remove it (Fedora:
# desktop_panel_advanced).
crit_panel_applets() {
    say "== Settings, Panel: add an applet, use it, remove it (Fedora: desktop_panel_advanced) [$(elapsed)]"
    local wings=/home/tester/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings start
    # Adding or removing an applet restarts all the panel's applets (SIGKILL:
    # "exited with code 137").
    start=$(g date +%s)
    ctl key meta_l-2
    sleep 2
    ctl click 640 400
    sleep 1
    shot PA0 > /dev/null
    settings_page panel-applet PA1
    wclick 763 96                        # Add applet
    sleep 2
    shot PA2-add > /dev/null
    wclick 777 406                       # On-screen Keyboard Button (third in the list): Add
    sleep 4
    shot PA3-added > /dev/null
    if g grep -q CosmicAppletOsk "$wings" && gt "$(changed PA1 PA3-added 0 0 400 32)" 0.003; then
        ok "[panel-advanced] an applet added in Settings appears on the panel at once"
        ctl click 226 15                 # its button, after the App Library button
        sleep 3
        shot PA4-osk > /dev/null
        check "[panel-advanced] the new applet works (its button opens the on-screen keyboard)" gt "$(changed PA3-added PA4-osk 0 350 1280 720)" 0.3
        ctl click 226 15
        sleep 3
        shot PA5 > /dev/null
        check "[panel-advanced] its button closes the on-screen keyboard again" lt "$(changed PA3-added PA5 0 350 1280 720)" 0.01
        wclick 786 90                    # Close (the Add applet pane)
        sleep 2
        wclick 790 360                   # the new applet's row (third): remove
        sleep 4
        shot PA6-removed > /dev/null
        if ! g grep -q CosmicAppletOsk "$wings" && lt "$(changed PA0 PA6-removed 0 0 400 32)" 0.001; then
            ok "[panel-advanced] removing it in Settings restores the panel"
        else
            fail "[panel-advanced] the applet did not go away"
        fi
    else
        fail "[panel-advanced] Add applet did not put the on-screen keyboard button on the panel ($(g tr -d ' \n' < "$wings" | head -c 200))"
    fi
    g sh -c "grep -q CosmicAppletOsk $wings && rm -f $wings" || true
    ctl key meta_l-q
    wait_gone 10 "Settings closed" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)' || g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    add_window "$start" "$(g date +%s)"
    ctl key meta_l-1
    sleep 2
}

# Print Settings: unlock, add a virtual printer, print its test page (Fedora:
# Printing_New_Printer with a virtual printer, Printing_PDF). No COSMIC app
# prints in 1.11. Test tools: cups-pdf; tester in lpadmin, as the Debian
# installer makes its first user.
crit_printing() {
    say "== Print Settings: unlock, add a PDF printer, print a test page (Fedora: Printing_New_Printer, Printing_PDF) [$(elapsed)]"
    local pdf
    if ! g test -x /usr/bin/system-config-printer; then
        known_issue "[print] Print Settings (system-config-printer) is not installed (newer builds of the package recommend it); installed for the test"
    elif ! g test -x /usr/sbin/cupsd; then
        known_issue "[print] cups is not installed: Print Settings says the printing service is not available (newer builds of the package recommend it); installed for the test"
    fi
    g sudo apt-get install -y -qq system-config-printer cups printer-driver-cups-pdf > "$OUT/apt-print.log" 2>&1 ||
        { fail "[print] could not install cups-pdf (see apt-print.log)"; return; }
    g sudo adduser -q tester lpadmin
    g sudo lpadmin -x vmtest-pdf 2> /dev/null || true
    g touch /tmp/print-start
    launch_app "print settings" system-config-p || { fail "[print] Print Settings did not start"; return; }
    win PR0
    wclick 395 56                        # Unlock
    if admin_prompt PR0 PR1-prompt; then
        ok "[print] Unlock asks for the admin password (COSMIC's prompt)"
    else
        fail "[print] Unlock showed no password prompt"
    fi
    sleep 4
    wclick 55 100                        # Add
    sleep 6
    # The window's size varies: its bottom buttons are placed from its
    # bottom right corner (WX1 WY1).
    shot PR2-new-printer > /dev/null
    set -- $(ctl winbox "$OUT/PR2-new-printer.ppm")
    [ "$1" != none ] || { fail "[print] no New Printer window"; g pkill -u tester -f "system-config-printer\.py"; return; }
    WX=$1 WY=$2
    local WX1=$3 WY1=$4
    # (winbox sees edges down to y=724; a taller window has no bottom here.)
    [ $(( WY1 - WY )) -ge 200 ] || { fail "[print] the New Printer window's bottom edge not found ($*)"; g pkill -u tester -f "system-config-printer\.py"; return; }
    wclick 98 151                        # Generic CUPS-PDF (second in the list)
    sleep 2
    ctl click $(( WX1 - 64 )) $(( WY1 - 31 ))   # Forward: its driver is found
    # Print Settings looks for the driver first: wait until the page heading
    # ("Select Device") changes; click Forward once more if it has not after
    # 16 s.
    local t
    for t in 2 4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40; do
        sleep 2
        shot PR3-describe > /dev/null
        gt "$(changed PR2-new-printer PR3-describe $(( WX + 10 )) $(( WY + 50 )) $(( WX + 200 )) $(( WY + 74 )))" 0.03 && break
        [ "$t" != 16 ] || ctl click $(( WX1 - 64 )) $(( WY1 - 31 ))
    done
    say "  the next page after ${t}s"
    wclick 339 155                       # Printer Name
    ctl key ctrl-a
    ctl type vmtest-pdf
    ctl click $(( WX1 - 64 )) $(( WY1 - 31 ))   # Apply
    # Sometimes CUPS asks for a user and password once more (Print Settings
    # adds the queue directly, not through polkit); lpadmin members may.
    if ! wait_for 8 "the printer added at once" sh -c 'lpstat -v | grep -q vmtest-pdf'; then
        shot PR4-cups-auth > /dev/null
        say "  CUPS asks for a user and password"
        set -- $(ctl winbox "$OUT/PR4-cups-auth.ppm" 250 100)
        if [ "$1" != none ]; then
            ctl click $(( $1 + 238 )) $(( $2 + 100 ))   # User name
            ctl type tester
            ctl click $(( $1 + 238 )) $(( $2 + 140 ))   # Password
            ctl type "$PASS"
            ctl key ret
        fi
    fi
    if wait_for 20 "the printer added" sh -c 'lpstat -v | grep -q vmtest-pdf'; then
        ok "[print] Add printer makes a virtual PDF printer (CUPS-PDF)"
        sleep 3
        shot PR5-test-page-question > /dev/null
        set -- $(ctl winbox "$OUT/PR5-test-page-question.ppm" 250 100)
        # The dialog "Print a test page?" (not always at the same place).
        if [ "$1" != none ]; then ctl click $(( $1 + 231 )) $(( $2 + 93 )); else say "  (the test page question not found)"; fi
        # cups-pdf names the file after the title: it may replace an old one.
        if wait_for 30 "the test page in ~/PDF" sh -c 'find ~/PDF -name "*.pdf" -newer /tmp/print-start | grep -q .'; then
            pdf=$(g sh -c 'find ~/PDF -name "*.pdf" -newer /tmp/print-start | head -n 1')
            check "[print] the test page is printed to a PDF file (${pdf##*/})" g sh -c "head -c 5 '$pdf' | grep -q '%PDF-'"
        else
            fail "[print] the test page did not come out (lpstat: $(g lpstat -W all -o | tail -n 1))"
        fi
        ctl key ret                      # Submitted: OK
        sleep 2
        ctl key esc                      # the printer's Properties: closed
        sleep 2
    else
        shot PR5-not-added > /dev/null
        fail "[print] Add printer did not add the printer"
    fi
    ctl key meta_l-q
    wait_gone 10 "Print Settings closed" pgrep -u tester -f "system-config-printer\.py" ||
        g pkill -u tester -f "system-config-printer\.py"
    sleep 2
    g sudo lpadmin -x vmtest-pdf 2> /dev/null || true
    # Installed together with cups (above), colord can be started by cupsd
    # before its own user exists, and fails once (Debian's install order).
    if g systemctl is-failed -q colord.service; then
        say "  colord failed while it was being installed with cups; reset"
        g sudo systemctl reset-failed colord.service
    fi
}

# COSMIC Store with PackageKit, from a local repository (local-repo.sh):
# an update (Fedora: desktop_update_graphical) and installing, opening and
# removing an app (Fedora: desktop_app_basic, package manager).
crit_store() {
    say "== COSMIC Store: an update and an app from a local repository (Fedora: desktop_update_graphical, package manager) [$(elapsed)]"
    local start
    start=$(g date +%s)
    if ! g test -x /usr/libexec/packagekitd; then
        known_issue "[store] PackageKit is not installed, so the Store lists no Debian software (newer builds of the package recommend it); installed for the test"
        g sudo apt-get install -y -qq packagekit > "$OUT/apt-packagekit.log" 2>&1 ||
            { fail "[store] could not install packagekit"; return; }
    fi
    g dpkg -s apt-config-icons > /dev/null 2>&1 ||
        known_issue "[store] the Store shows no app icons: Debian downloads them only with apt-config-icons (newer builds of the package recommend it)"
    "${SSH[@]}" sudo sh -s setup < "$HERE/local-repo.sh" || { fail "[store] the local repository could not be set up"; return; }
    launch_app store cosmic-store || { fail "[store] the Store did not start"; "${SSH[@]}" sudo sh -s restore < "$HERE/local-repo.sh"; return; }
    sleep 5
    win ST0
    ctl scroll $((WX + 149)) $((WY + 335)) down 10
    sleep 1
    wclick 86 430                        # Updates, last in the sidebar
    sleep 4
    wclick 572 186                       # Check for updates
    if wait_for 30 "the repository read" test -e /var/lib/apt/lists/_srv_vmtest-repo_dists_vmtest_main_binary-amd64_Packages; then
        sleep 6
        shot ST1-updates > /dev/null
        wclick 494 179                   # System Packages: Update
        admin_prompt ST1-updates ST2-prompt || say "  (no password prompt for the update)"
        if wait_for 60 "vmtest-update 2.0 installed" sh -c 'dpkg-query -W -f="\${Version}" vmtest-update | grep -qx 2.0'; then
            ok "[store] Check for updates finds an update and Update installs it (with the admin password)"
        else
            fail "[store] the update was not installed (vmtest-update $(g dpkg-query -W -f='${Version}' vmtest-update))"
        fi
        sleep 3
        shot ST3-updated > /dev/null
    else
        fail "[store] Check for updates did not refresh the package lists (NetworkManager: $(g nmcli -t -f STATE general); PackageKit refuses while offline)"
    fi
    # The Store reads the app catalogue when it starts.
    ctl key meta_l-q
    wait_gone 15 "the Store closed" pgrep -u tester -x cosmic-store
    launch_app store cosmic-store
    sleep 5
    win ST4
    wclick 79 26                         # Search
    sleep 1
    ctl type "VM Test"
    ctl key ret
    sleep 5
    shot ST5-search > /dev/null
    wclick 489 85                        # the result
    sleep 4
    shot ST6-app > /dev/null
    wclick 534 193                       # Install
    admin_prompt ST6-app ST7-prompt || say "  (no password prompt for the install)"
    if wait_for 60 "vmtest-app installed" test -x /usr/bin/vmtest-app; then
        ok "[store] an app found by search installs (with the admin password)"
        sleep 3
        wclick 532 193                   # Open
        if wait_for 15 "the app running" pgrep -u tester -x zenity; then
            ok "[store] Open starts the installed app"
            sleep 2
            ctl key ret
            wait_gone 10 "the app closed" pgrep -u tester -x zenity
        else
            fail "[store] Open did not start the app"
        fi
        sleep 2
        shot ST8 > /dev/null
        wclick 623 193                   # Uninstall
        sleep 3
        wclick 645 281                   # "Uninstall VM Test App?": Uninstall
        admin_prompt ST8 ST9-prompt || say "  (no password prompt for the removal)"
        check "[store] Uninstall removes it" wait_for 60 "vmtest-app removed" test ! -e /usr/bin/vmtest-app
    else
        fail "[store] the app was not installed"
    fi
    ctl key meta_l-q
    sleep 2
    "${SSH[@]}" sudo sh -s restore < "$HERE/local-repo.sh"
    add_window "$start" "$(g date +%s)"
}

# COSMIC Store with Flatpak (the package suggests flatpak): an app from a
# local, signed Flatpak repository (local-flatpak.sh; no network): search,
# install, open, uninstall; a source imported from a .flatpakrepo file and
# removed again; a category page. Flatpak's apps show in a session only when
# it started after flatpak was installed (XDG_DATA_DIRS), as after
# installing it on a real system: log out and in first.
crit_flatpak() {
    say "== COSMIC Store with Flatpak: install, open, uninstall; a source imported and removed; a category (cosmic-store TESTING.md) [$(elapsed)]"
    local mark=/home/tester/.var/app/org.example.VmtestFlat/data/vmtest-flat-ran
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq flatpak > /dev/null 2>&1; then
        fail "[flatpak] could not install flatpak"
        return
    fi
    "${SSH[@]}" sudo sh -s setup < "$HERE/local-flatpak.sh" || { fail "[flatpak] the local Flatpak repository could not be set up"; return; }
    g cp /srv/vmtest.flatpakrepo /home/tester/Downloads/
    relogin
    launch_app store cosmic-store || { fail "[flatpak] the Store did not start"; return; }
    sleep 5
    win FL0
    wclick 79 26; sleep 1                    # Search
    ctl type "VM Test Flatpak"
    ctl key ret
    sleep 6
    wclick 489 85; sleep 4                   # the result
    shot FL1-app > /dev/null
    wclick 534 193                           # Install
    admin_prompt FL1-app FL2-prompt || say "  (no password prompt for the install)"
    if wait_for 60 "the Flatpak installed" sh -c 'flatpak list --system --app | grep -q org.example.VmtestFlat'; then
        ok "[flatpak] an app from a Flatpak repository installs from the Store"
        sleep 3
        wclick 532 193                       # Open
        check "[flatpak] Open runs it (in its sandbox)" wait_for 20 "the Flatpak ran" test -e "$mark"
        sleep 2
        shot FL3 > /dev/null
        wclick 623 193; sleep 3              # Uninstall
        ctl click 856 413                    # "Uninstall VM Test Flatpak?": Uninstall
        admin_prompt FL3 FL4-prompt || say "  (no password prompt for the removal)"
        check "[flatpak] Uninstall removes it" wait_for 60 "the Flatpak removed" sh -c '! flatpak list --system --app | grep -q org.example.VmtestFlat'
    else
        fail "[flatpak] the Flatpak was not installed"
    fi
    # Sources: Import a .flatpakrepo, chosen in the file chooser (pick). Right
    # after a login its first search sometimes finds nothing: up to three
    # tries.
    wclick 710 26; sleep 3                   # the gear: Software repositories
    shot FL5-sources > /dev/null
    local try added=1
    for try in 1 2 3; do
        wclick 792 418; sleep 3              # Import
        pick vmtest.flatpakrepo FL5b-chooser
        if wait_for 15 "the source added" sh -c 'flatpak remotes --user | grep -q "^vmtest"'; then added=0; break; fi
        ctl key esc; sleep 2                 # the chooser, if it is still open
    done
    if [ $added = 0 ]; then
        ok "[flatpak] Import adds a Flatpak source from a .flatpakrepo file (signed)"
        sleep 4
        shot FL6-imported > /dev/null
        wclick 764 374                       # its Remove
        check "[flatpak] Remove in the Store removes the source" wait_for 20 "the source removed" sh -c '! flatpak remotes --user | grep -q "^vmtest"'
    else
        fail "[flatpak] Import did not add the source (FL5-sources.png)"
    fi
    wclick 785 90; sleep 2                   # Close (repositories)
    shot FL7-explore > /dev/null
    wclick 85 394; sleep 4                   # Utilities
    shot FL8-utilities > /dev/null
    check "[store] a category page lists apps (Utilities)" gt "$(changed FL7-explore FL8-utilities $((WX + 350)) $((WY + 60)) $((WX + 840)) $((WY + 450)))" 0.2
    ctl key meta_l-q
    sleep 2
    "${SSH[@]}" sudo sh -s restore < "$HERE/local-flatpak.sh"
    g sh -c 'rm -f ~/Downloads/vmtest.flatpakrepo; rm -rf ~/.var/app/org.example.VmtestFlat'
    g sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --autoremove flatpak > /dev/null 2>&1
}

# Automatic login (NixOS: cosmic-autologin). COSMIC has no setting for it;
# greetd's initial_session starts a session once, when greetd starts.
crit_autologin() {
    say "== automatic login (greetd initial_session; NixOS: cosmic-autologin) [$(elapsed)]"
    local conf=/etc/greetd/cosmic-greeter.toml start old
    start=$(g date +%s)
    ctl click 640 400
    sleep 1
    shot AU0-desktop > /dev/null
    old=$(g pgrep -u tester -x cosmic-panel)
    g sudo sh -c "cp $conf $conf.vmtest && printf '\n[initial_session]\ncommand = \"/usr/bin/start-cosmic\"\nuser = \"tester\"\n' >> $conf"
    # greetd's runfile marks a restart, which skips initial_session.
    g sudo sh -c 'rm -f /run/greetd.run && systemctl --no-block restart display-manager'
    if wait_for 60 "a new session without the login screen" sh -c "p=\$(pgrep -u tester -x cosmic-panel) && [ \"\$p\" != '$old' ] && ! pgrep -u cosmic-greeter -x cosmic-greeter"; then
        sleep 15
        shot AU1-autologin 0.9
        ok "[autologin] the session starts without the login screen"
        if lt "$(changed AU0-desktop AU1-autologin 0 715 300 800)" 0.01 && lt "$(changed AU0-desktop AU1-autologin 980 715 1280 800)" 0.01; then
            ok "[autologin] the desktop looks as after a normal login"
        else
            # Seen after password logins too (then in AU0): the dock's clear
            # area beside it sometimes shows leftover pixels until the next
            # login.
            known_issue "[dock] stray pixels beside the dock after one of two logins (AU0-desktop.png: before, AU1-autologin.png: automatic); now and then in the VM, not confirmed upstream"
        fi
    else
        shot AU1-no-autologin > /dev/null
        fail "[autologin] no session started by itself"
    fi
    g sudo mv "$conf.vmtest" "$conf"
    # Back to a session with a password login (it unlocks the keyring).
    if g pgrep -u tester -x cosmic-panel > /dev/null; then
        logout_to_greeter tester
    else
        g sudo systemctl restart display-manager
        wait_for 60 "login screen" pgrep -u cosmic-greeter -x cosmic-greeter
        sleep 8
    fi
    log_in
    add_window "$start" "$(g date +%s)"
}

# power_menu_restart: the panel's power menu, Restart, Confirm.
power_menu_restart() {
    ctl click 1259 15         # the power icon, top right
    sleep 2
    shot R1-power-menu > /dev/null
    ctl click 1099 233        # Restart
    sleep 2
    shot R2-restart-dialog > /dev/null
    ctl click 813 426         # Confirm
}

# Fedora Basic "basic networking" (the desktop side): a wired connection set to
# a static address in Settings, then disconnected and connected again there.
# On a second network card plugged in for the test (the first one carries the
# test's SSH), on its own QEMU network. Settings edits a connection in
# nm-connection-editor (recommended by the package); it and Settings must be
# started in the session (from the launcher): started over SSH, polkit does
# not let them change anything.
crit_network() {
    say "== Settings, Network: a static address on a wired connection, disconnect and connect (Fedora: basic networking) [$(elapsed)]"
    local dev con addr i
    ctl nic plug
    if ! wait_for 30 "the second network card connected" sh -c 'nmcli -t -f DEVICE,STATE dev | grep -q "^enp2s0:connected$"'; then
        fail "[network] the second network card (enp2s0) did not connect"
        ctl nic unplug
        return
    fi
    dev=enp2s0
    con=$(g nmcli -g GENERAL.CONNECTION dev show $dev)
    g pkill -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    # (pgrep -x cosmic-settings would also match cosmic-settings-daemon: the
    # kernel keeps 15 characters of a process name.)
    wait_gone 10 "Settings closed" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    # ("settings" alone finds Print Settings first once it has been used.)
    launch_app "cosmic settings" cosmic-settings
    wait_for 20 "Settings running" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)'
    sleep 2
    win NE0
    wclick 124 74                            # Network & wireless
    sleep 3
    wclick 572 228                           # the second adapter, enp2s0
    sleep 3
    # The connection's menu, then Settings in it (again if the editor does
    # not come, once).
    for i in 1 2; do
        wclick 774 189
        sleep 2
        shot NE0-menu-$i > /dev/null
        wclick 684 257
        wait_for 15 "nm-connection-editor running" pgrep -u tester -f nm-connection-editor && break
        shot NE0-no-editor-$i > /dev/null
    done
    if ! g pgrep -u tester -f nm-connection-editor > /dev/null; then
        fail "[network] the connection's Settings did not open its editor (NE0-menu-2.png, NE0-no-editor-2.png)"
        ctl key meta_l-q
        ctl nic unplug
        return
    fi
    sleep 3
    ctl key meta_l-m                         # maximized: its layout is fixed
    sleep 3
    shot NE1-editor > /dev/null
    ctl click 507 132                        # IPv4 Settings
    sleep 2
    ctl click 670 180                        # Method
    sleep 2
    ctl click 150 244                        # Manual (two below Automatic)
    sleep 2
    ctl click 1218 258                       # Add
    sleep 1
    ctl type "10.0.2.20"
    ctl key tab
    ctl type "24"
    ctl key tab
    ctl type "10.0.2.2"
    ctl key ret
    sleep 1
    shot NE2-static > /dev/null
    ctl click 1229 704                       # Save
    # polkit asks for the admin password unless it still remembers it (a few
    # minutes after another admin action): answer only a prompt that is there.
    sleep 3
    if ! g sh -c "nmcli -g ipv4.method con show '$con' | grep -q manual"; then
        if admin_prompt NE2-static NE3-prompt; then say "  the admin password asked for"; fi
    fi
    if wait_for 15 "the connection saved" sh -c "nmcli -g ipv4.method con show '$con' | grep -q manual"; then
        ok "[network] the static address is saved (ipv4.method manual, $(g nmcli -g ipv4.addresses con show "$con"))"
    else
        fail "[network] the static address was not saved (NE2-static.png)"
    fi
    wait_gone 10 "the editor closed" pgrep -u tester -f nm-connection-editor || g pkill -u tester -f nm-connection-editor
    sleep 2
    win NE4
    wclick 774 189                           # the menu
    sleep 2
    wclick 695 228                           # Disconnect
    if wait_for 15 "disconnected" sh -c "nmcli -t -f DEVICE,STATE dev | grep -q '^$dev:disconnected$'"; then
        ok "[network] Disconnect in Settings disconnects it"
    else
        fail "[network] Disconnect in Settings did not disconnect $dev"
    fi
    sleep 2
    wclick 707 189                           # Connect
    if wait_for 20 "connected" sh -c "nmcli -t -f DEVICE,STATE dev | grep -q '^$dev:connected$'"; then
        addr=$(g ip -4 -br addr show $dev | awk '{ print $3 }')
        if [ "$addr" = 10.0.2.20/24 ] && g ping -c 1 -W 3 -I $dev 10.0.2.2 > /dev/null 2>&1; then
            ok "[network] Connect brings it back with the static address ($addr), which reaches the gateway"
        else
            fail "[network] after Connect: address ${addr:-none}, gateway $(g ping -c 1 -W 3 -I $dev 10.0.2.2 > /dev/null 2>&1 && echo reached || echo not reached)"
        fi
    else
        fail "[network] Connect in Settings did not connect $dev"
    fi
    ctl key meta_l-q
    sleep 2
    g sudo nmcli con delete "$con" > /dev/null 2>&1
    ctl nic unplug
    sleep 2
}

# Two displays (boot 4: a second graphics card, virtio-gpu-pci, whose output is
# Virtual-2). Fedora Final "dual monitor setup", Settings' Displays page,
# cosmic-comp#2727 (disabling an output kills the session). The VM's pointer
# is mapped to Virtual-2 (the compositor puts an absolute tablet on one
# output): clicks land there, so Settings opens there.
shot2() { local r; r=$(ctl shot2 "$OUT/$1.png") || { fail "screenshot $1 (second display)"; return 1; }; say "  screenshot $1.png (second display, $r)"; }
# dshot 1|2 NAME: screenshot of the first or the second display.
dshot() { if [ "$1" = 1 ]; then shot "$2" > /dev/null; else shot2 "$2"; fi; }
randr_pos() { gs cosmic-randr list --kdl 2> /dev/null | awk -v o="\"$1\"" '$1 == "output" { cur = $2 } cur == o && $1 == "position" { print $2, $3; exit }'; }
crit_dual() {
    say "== two displays: both show the desktop, arrange in Settings, mirror, turn one off (Fedora: dual monitor setup) [$(elapsed)]"
    local comp start t
    comp=$(g pgrep -u tester -x cosmic-comp)
    # Outputs that change (mirroring, off and on) restart the panels'
    # applets on them (exit code 137): a closing window for all of it.
    start=$(g date +%s)
    shot DU1-first > /dev/null
    shot2 DU2-second
    if [ "$(randr_pos Virtual-1)" = "0 0" ] && [ "$(randr_pos Virtual-2)" = "1280 0" ]; then
        ok "[dual] both displays are on, side by side (Virtual-1 at 0,0, Virtual-2 at 1280,0)"
    else
        fail "[dual] the displays: Virtual-1 at $(randr_pos Virtual-1), Virtual-2 at $(randr_pos Virtual-2)"
    fi
    # The panel and the dock on each (the same top bar; not blank).
    check "[dual] the panel and the dock show on both displays" lt "$(changed DU1-first DU2-second 0 0 1280 32)" 0.05
    check "[dual] the second display is not blank" lt "$(ctl shot2 "$OUT/DU2b.png" | sed 's/.*top=//')" 0.9

    # Settings, Displays: drag display 2 below display 1.
    gs sh -c 'setsid cosmic-settings displays < /dev/null > /dev/null 2>&1 &'
    sleep 6
    shot2 DU3-settings
    ctl drag 837 313 735 370
    sleep 3
    shot2 DU4-dragged
    set -- $(randr_pos Virtual-2)
    if [ "${2:-0}" = 800 ]; then
        ok "[dual] dragging display 2 below display 1 in Settings moves it there (Virtual-2 at $1,$2)"
    else
        fail "[dual] dragging display 2 in Settings did not put it below display 1 (Virtual-2 at ${1:-?},${2:-?})"
    fi
    ctl key meta_l-q
    sleep 2
    gs cosmic-randr position Virtual-2 1280 0 > /dev/null 2>&1
    sleep 3

    # A terminal: it opens on the display with the keyboard focus (A); the
    # other is B. Mirror A on B; end mirroring; turn A off: the session goes
    # on and the window moves to B; turn A on: the window comes back.
    local a b
    ctl key meta_l-t
    sleep 4
    shot DU5-terminal > /dev/null
    shot2 DU6-terminal
    if [ "$(ctl winbox "$OUT/DU5-terminal.ppm")" != none ] && [ "$(ctl winbox "$OUT/DU6-terminal.ppm")" = none ]; then
        a=1 b=2
    elif [ "$(ctl winbox "$OUT/DU5-terminal.ppm")" = none ] && [ "$(ctl winbox "$OUT/DU6-terminal.ppm")" != none ]; then
        a=2 b=1
    else
        fail "[dual] a new window does not show on exactly one display (DU5, DU6)"
        ctl key meta_l-q
        return
    fi
    ok "[dual] a new window opens on one display (Virtual-$a, the one with the keyboard focus)"
    gs cosmic-randr mirror Virtual-$b Virtual-$a > /dev/null 2>&1
    sleep 4
    shot DU7-mirror > /dev/null
    shot2 DU8-mirror
    if lt "$(changed DU7-mirror DU8-mirror)" 0.01; then
        ok "[dual] mirroring shows one display on the other (Virtual-$a on Virtual-$b)"
    else
        fail "[dual] Virtual-$b does not mirror Virtual-$a (changed $(changed DU7-mirror DU8-mirror))"
    fi
    gs cosmic-randr enable Virtual-$b > /dev/null 2>&1
    sleep 4
    dshot $b DU9-extended
    check "[dual] enabling it again ends mirroring (the window only on Virtual-$a)" test "$(ctl winbox "$OUT/DU9-extended.ppm")" = none
    gs cosmic-randr disable Virtual-$a > /dev/null 2>&1
    sleep 4
    dshot $b DU10-one-off
    if [ "$(g pgrep -u tester -x cosmic-comp)" != "$comp" ]; then
        fail "[dual] turning a display off ended the session (cosmic-comp restarted; cosmic-comp#2727)"
        return
    fi
    check "[dual] turning off a display moves its window to the other one; the session goes on" test "$(ctl winbox "$OUT/DU10-one-off.ppm")" != none
    gs cosmic-randr enable Virtual-$a > /dev/null 2>&1
    sleep 4
    dshot $a DU11-back
    check "[dual] turned on again, the window is back on it" test "$(ctl winbox "$OUT/DU11-back.ppm")" != none
    ctl key meta_l-q
    sleep 2

    # The lock screen on both displays; the password unlocks.
    ctl key meta_l-esc
    sleep 4
    shot DU12-locked > /dev/null
    shot2 DU13-locked
    if [ "$(ctl lockcard "$OUT/DU12-locked.ppm")" = yes ] && [ "$(ctl lockcard "$OUT/DU13-locked.ppm")" = yes ]; then
        ok "[dual] Super+Escape locks both displays"
    else
        fail "[dual] the lock screen is not on both displays (first: $(ctl lockcard "$OUT/DU12-locked.ppm"), second: $(ctl lockcard "$OUT/DU13-locked.ppm"))"
    fi
    unlock DU14-unlocked
    check "[dual] the password unlocks both" test "$(ctl lockcard "$OUT/DU14-unlocked.ppm")" = no
    t=$(g pgrep -u tester -x cosmic-comp)
    check "[dual] the same session throughout (cosmic-comp $comp)" test "$t" = "$comp"
    add_window "$start" "$(g date +%s)"
}

criteria() {
    crit_panel
    crit_wm
    crit_console
    crit_open
    crit_apps
    crit_layout
    crit_toolkits
    crit_sdl
    crit_graphics
    crit_settings
    crit_appearance
    crit_style_dock
    crit_datetime
    crit_sound_settings
    crit_network             # before suspend: after it a card plugged in does not reach the guest
    crit_about
    crit_idle
    crit_suspend
    crit_shutdown_cancel
    crit_archive
    crit_panel_applets
    crit_printing
    crit_translations
    crit_store
    crit_flatpak
    crit_password
    crit_notifications
    crit_keyring first
    autostart_setup          # checked after the reboot (autostart_check)
    crit_language_setup      # checked after the next log in (crit_language_check)
}
