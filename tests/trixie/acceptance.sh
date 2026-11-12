# COSMIC's own acceptance checklists, automated where a VM allows it.
# Sourced by vm-session.sh (uses its helpers: say ok fail known_issue check
# shot changed gt g gs wait_for wait_gone running ctl, and $OUT $W).
#
# Each check is tagged with the item of upstream's TESTING.md it covers, e.g.
# [launcher-4]; ACCEPTANCE.md lists every item, how it is covered here, and
# which ones need real hardware. Coordinates are for the VM's 1280x800 screen
# with COSMIC's default layout (windows open centred).

# launch_app SEARCH PROCESS: start an app from the launcher, as a person would.
launch_app() {
    ctl key meta_l
    sleep 2
    ctl type "$1"
    sleep 2
    ctl key ret
    wait_for 20 "$2 running" pgrep -u tester -x "$2" && sleep 3
}

# win NAME: screenshot NAME and set WX WY to the focused window's top-left
# corner (new windows cascade, so they are not always centred);
# wclick DX DY [BUTTON]: click relative to it.
win() {
    shot "$1" > /dev/null
    set -- $(ctl winbox "$OUT/$1.ppm")
    if [ "$1" = none ]; then
        WX=211 WY=115
        say "  ($1: focused window not found, assuming a centred one)"
    else
        WX=$1 WY=$2
    fi
}
wclick() { ctl click $((WX + $1)) $((WY + $2)) ${3:-}; }

# newest_png_size: "WxH" of the newest screenshot in ~/Pictures/Screenshots.
newest_png_size() {
    g sh -c 'f=$(ls -t ~/Pictures/Screenshots/*.png | head -n 1) &&
             python3 -c "import struct, sys; d = open(sys.argv[1], \"rb\").read(24); print(\"%dx%d\" % struct.unpack(\">II\", d[16:24]))" "$f"'
}

acc_edit() {
    say "== COSMIC Text Editor checklist (cosmic-edit TESTING.md) [$(elapsed)]"
    launch_app "text editor" cosmic-edit || { fail "[edit] the editor did not start"; return; }
    ctl type $'line one\nline two\nline three'
    # Copy the last two lines (select up from the end), paste at the end.
    ctl key shift-up shift-home ctrl-c ctrl-end ctrl-v
    sleep 1
    ctl key ctrl-s
    sleep 4
    ctl type "edit-check.txt"
    ctl key ret
    sleep 3
    check "[edit-1,2,3] three lines typed, the last two copied and pasted at the end (four lines)" \
        test "$(g cat edit-check.txt 2>&1)" = $'line one\nline two\nline threeline two\nline three'
    ctl key ctrl-z ret ctrl-v ctrl-z ctrl-shift-z ctrl-s
    sleep 2
    check "[edit-4..9] undo, newline, paste, undo, redo, save (five lines)" \
        test "$(g cat edit-check.txt 2>&1)" = $'line one\nline two\nline three\nline two\nline three'
    # Upstream's list says Esc twice; since 1.11.0 text inputs no longer
    # capture Esc, so one Esc closes Find and a second one drops the selection.
    ctl key ctrl-f
    sleep 1
    ctl type "one"
    ctl key ret
    sleep 1
    ctl key esc ctrl-x ctrl-end ret ctrl-v ctrl-s
    sleep 2
    check "[edit-10..14] find, cut the match, paste it on a new line, save again (six lines)" \
        test "$(g cat edit-check.txt 2>&1)" = $'line \nline two\nline three\nline two\nline three\none'
    shot E-editor > /dev/null
    ctl key meta_l-q
    wait_gone 10 "cosmic-edit closed" pgrep -u tester -x cosmic-edit || fail "[edit-19] Super+Q did not close the editor"
    launch_app "text editor" cosmic-edit || { fail "[edit-20] the editor did not start again"; return; }
    ctl key ctrl-o
    sleep 4
    ctl type "edit-check"                    # the dialog searches as you type
    sleep 2
    win E-open-dialog
    wclick 134 172                           # the one result
    sleep 1
    wclick 800 430                           # Open
    sleep 3
    ctl key ctrl-end
    ctl type "appended"
    ctl key ctrl-s
    sleep 2
    check "[edit-20] the file opens again through the Open dialog (an edit lands in it)" \
        test "$(g tail -n 1 edit-check.txt 2>&1)" = oneappended
    # The editor stays open on workspace 1 for the launcher checks.
}

acc_launcher() {
    say "== COSMIC Launcher checklist (cosmic-launcher TESTING.md) [$(elapsed)]"
    # Workspaces are dynamic: workspace 2 exists only while workspace 1 has a
    # window (the editor). A terminal on workspace 2 gets a title of its own.
    ctl key meta_l-2
    sleep 2
    ctl key meta_l-t
    sleep 6
    ctl type "mkdir -p /tmp/ws2dir && cd /tmp/ws2dir && clear"
    ctl key ret
    sleep 2
    shot L-workspace-2 > /dev/null
    ctl key meta_l-1
    sleep 3
    shot L-workspace-1 > /dev/null
    d=$(changed L-workspace-2 L-workspace-1 0 40 1280 700)
    gt "$d" 0.01 || fail "[launcher] setup: Super+1 did not leave workspace 2 (changed $d)"

    ctl key meta_l
    sleep 2
    shot L-open > /dev/null
    ctl type "zz"
    sleep 1
    ctl key backspace backspace
    sleep 2
    shot L-cleared > /dev/null
    d=$(changed L-open L-cleared)
    if gt 0.01 "$d"; then ok "[launcher-6] removing typed text shows the open windows again"; else fail "[launcher-6] the list differs after removing typed text (changed $d)"; fi
    ctl type "ws2dir"
    sleep 2
    shot L-window-result > /dev/null
    ctl key ret
    sleep 3
    shot L-switched > /dev/null
    ctl type "touch /tmp/launcher-focus"
    ctl key ret
    sleep 2
    d=$(changed L-workspace-2 L-switched 0 40 1280 700)
    if gt 0.02 "$d" && g test -e /tmp/launcher-focus; then
        ok "[launcher-3,4,7,8] a window on workspace 2 is found, listed first; Enter moves to workspace 2 and focuses it"
    else
        fail "[launcher-3,4,7,8] Enter on the window did not move to it and focus it (changed $d, typed command ran: $(g test -e /tmp/launcher-focus && echo yes || echo no))"
    fi

    ctl key meta_l
    sleep 2
    ctl type "= 6*7"
    sleep 3
    ctl key ret                              # fills in the result: "= 42"
    sleep 1
    ctl key ctrl-a ctrl-x
    sleep 1
    ctl key esc
    sleep 1
    case "$(gs timeout 5 wl-paste 2>&1)" in
        "= 42") ok "[launcher-12] = calculates (= 6*7 gives 42)"
                ok "[launcher-2] text cut in the launcher can be pasted after it closed" ;;
        "= 6*7") ok "[launcher-2] text cut in the launcher can be pasted after it closed"
                 if g test -x /usr/bin/qalc; then fail "[launcher-12] = did not calculate"
                 else known_issue "[launcher-12] = needs qalc, not installed (newer builds of the package depend on it)"; fi ;;
        *) fail "[launcher-2,12] nothing cut from the launcher reached the clipboard ($(gs timeout 5 wl-paste 2>&1 | head -c 60))" ;;
    esac

    ctl key meta_l
    sleep 2
    ctl type ": touch /tmp/launcher-sh"
    sleep 1
    ctl key ret
    sleep 2
    check "[launcher-11] : runs a command in sh" g test -e /tmp/launcher-sh
    ctl key meta_l
    sleep 2
    ctl type "t: touch /tmp/launcher-t"
    sleep 1
    ctl key ret
    sleep 5
    check "[launcher-10] t: runs a command in a terminal" g test -e /tmp/launcher-t
    ctl key ret                              # "Press Enter" closes that terminal
    sleep 2

    ctl key meta_l
    sleep 2
    ctl type "shop"
    sleep 3
    ctl key ret
    if wait_for 20 "cosmic-store running" pgrep -u tester -x cosmic-store; then
        ok "[launcher-13] \"shop\" gives the COSMIC Store first"
        sleep 4
        ctl key meta_l-q
        wait_gone 15 "cosmic-store closed" pgrep -u tester -x cosmic-store || say "  cosmic-store still running (informational)"
    else
        fail "[launcher-13] \"shop\" did not start the COSMIC Store"
    fi

    # [launcher-9] Settings panels; continues with the Power & battery item.
    ctl key meta_l
    sleep 2
    ctl type "power"
    sleep 3
    ctl key ret
    if wait_for 20 "cosmic-settings running" pgrep -u tester -x cosmic-settings &&
       g sh -c 'pgrep -a -u tester -x cosmic-settings | grep -q " power"'; then
        ok "[launcher-9] \"power\" opens Settings on Power & battery"
        sleep 4
        win L-settings
        acc_settings_power
        wclick 429 26                        # focus Settings (header bar)
        ctl key meta_l-q
        sleep 3
    else
        fail "[launcher-9] \"power\" did not open the Power & battery page"
    fi
}

# Opens the panel's battery applet; a second click if the first one only
# reset its state (seen after a choice in it closed it).
open_battery_applet() {
    shot P-closed > /dev/null
    ctl click 1191 15
    sleep 2
    shot "$1" > /dev/null
    if gt 0.2 "$(changed P-closed "$1" 920 40 1280 330)"; then
        ctl click 1191 15
        sleep 2
        shot "$1" > /dev/null
    fi
}

acc_settings_power() {
    if ! g systemctl is-active --quiet power-profiles-daemon.service; then
        known_issue "[settings-power] power-profiles-daemon not installed (newer builds of the package recommend it)"
        return
    fi
    # The VM offers power-saver and balanced only (no performance driver);
    # COSMIC still shows High performance, and choosing it silently fails.
    open_battery_applet P-applet-balanced
    ctl key esc
    sleep 1
    wclick 362 168                           # Settings: Extended battery life
    sleep 2
    check "[settings-power] Settings' power mode takes effect (power-saver)" test "$(g powerprofilesctl get)" = power-saver
    open_battery_applet P-applet-saver
    d=$(changed P-applet-balanced P-applet-saver 1235 55 1265 145)
    if gt "$d" 0.02; then ok "[settings-power] the panel applet shows the new mode"; else fail "[settings-power] the panel applet still shows the old mode (changed $d)"; fi
    ctl click 974 117                        # applet: Balanced
    sleep 2
    check "the applet's Balanced sets it back" test "$(g powerprofilesctl get)" = balanced
    ctl key esc
    sleep 1
}

acc_osd() {
    say "== COSMIC OSD checklist: the log out dialog (cosmic-osd TESTING.md) [$(elapsed)]"
    # Careful: Enter or Space on Confirm logs out, and the dialog logs out by
    # itself after 60 s. Only Tab, Space on Cancel, and Escape are used.
    comp=$(g pgrep -u tester -x cosmic-comp)
    shot O-before > /dev/null
    ctl key meta_l-shift-esc
    sleep 3
    shot O-dialog > /dev/null
    d=$(changed O-before O-dialog)
    if ! gt "$d" 0.05; then fail "[osd-7] Super+Shift+Escape did not open the log out dialog (changed $d)"; return; fi
    ctl key tab
    sleep 1
    shot O-tab > /dev/null
    d=$(changed O-dialog O-tab 540 420 905 470)
    if gt "$d" 0.02; then ok "[osd-7] Tab moves between the dialog's buttons"; else fail "[osd-7] Tab did not move the focus (changed $d)"; fi
    ctl key tab
    sleep 1
    shot O-tab-2 > /dev/null
    if gt 0.005 "$(changed O-dialog O-tab-2 540 420 905 470)"; then
        ctl key spc
        sleep 2
        shot O-space > /dev/null
        d=$(changed O-before O-space)
        if gt 0.02 "$d"; then
            ok "[osd-8] Space on Cancel closes the dialog"
        else
            known_issue "[osd-8] Space on Cancel does not close the log out dialog (Enter and Escape do; not confirmed upstream)"
            ctl key esc
            sleep 2
        fi
    else
        say "  focus not back on Cancel after two Tabs; Space not tried"
        ctl key esc
        sleep 2
    fi
    ctl key meta_l-shift-esc
    sleep 3
    ctl key esc
    sleep 2
    shot O-escape > /dev/null
    d=$(changed O-before O-escape)
    if gt 0.02 "$d"; then ok "[osd-9] Escape closes the dialog"; else fail "[osd-9] Escape did not close the dialog (changed $d)"; ctl key esc; fi
    check "still logged in (same cosmic-comp)" test "$(g pgrep -u tester -x cosmic-comp)" = "$comp"
}

acc_files() {
    say "== COSMIC Files checklist (cosmic-files TESTING.md) [$(elapsed)]"
    g sh -c 'rm -rf ftest && mkdir ftest && touch ftest/.hidden-file'
    gs sh -c 'setsid cosmic-files /home/tester/ftest < /dev/null > /dev/null 2>&1 &'
    wait_for 20 "cosmic-files running" pgrep -u tester -x cosmic-files || { fail "[files] cosmic-files did not start"; return; }
    sleep 4
    win F-window
    # High enough in the empty folder that the menu opens downwards.
    wclick 400 150 right
    sleep 2
    shot F-context-menu > /dev/null
    wclick 448 205                           # New file... (the menu's second item)
    sleep 2
    ctl type "made-by-files.txt"
    ctl key ret
    sleep 2
    check "[files-7] right-click, New file" g test -f ftest/made-by-files.txt
    ctl key ctrl-shift-n
    sleep 2
    ctl type "sub"
    ctl key ret
    sleep 2
    check "[files-6] New folder (Ctrl+Shift+N)" g test -d ftest/sub
    ctl key end f2                           # folders first: End is the file
    sleep 2
    ctl key ctrl-a
    ctl type "renamed.txt"
    ctl key ret
    sleep 2
    check "[files-9] rename (F2)" g test -f ftest/renamed.txt -a ! -e ftest/made-by-files.txt
    ctl key end ctrl-c home ret              # copy the file, go into sub
    sleep 2
    ctl key ctrl-v
    sleep 2
    check "[files-6,24] into the new folder; copy and paste a file" g test -f ftest/sub/renamed.txt
    ctl key backspace                        # back
    sleep 2
    ctl key end delete
    sleep 2
    check "[files-11] Delete moves to the trash" g test ! -e ftest/renamed.txt -a -f .local/share/Trash/files/renamed.txt
    ctl key home ret
    sleep 2
    ctl key end shift-delete
    sleep 2
    shot F-permanent-delete > /dev/null
    ctl key ret                              # the dialog's focused button: Delete
    sleep 2
    check "[files-12] Shift+Delete deletes permanently, after asking" \
        g sh -c 'test ! -e ftest/sub/renamed.txt && test "$(ls .local/share/Trash/files | wc -l)" = 1'
    ctl key backspace
    sleep 2
    shot F-list > /dev/null
    ctl key ctrl-h
    sleep 2
    shot F-hidden > /dev/null
    d=$(changed F-list F-hidden $((WX + 319)) $((WY + 160)) $((WX + 829)) $((WY + 220)))
    ctl key ctrl-h
    sleep 2
    if gt "$d" 0.01; then ok "[files-18] Ctrl+H shows hidden files"; else fail "[files-18] Ctrl+H did not show .hidden-file (changed $d)"; fi

    # Thumbnails of the screenshots taken earlier.
    ctl key meta_l-q
    sleep 2
    gs sh -c 'setsid cosmic-files /home/tester/Pictures/Screenshots < /dev/null > /dev/null 2>&1 &'
    sleep 8
    win F-thumbnails
    n=$(g sh -c 'find ~/.cache/thumbnails -path "*/fail/*" -prune -o -type f -name "*.png" -print | wc -l')
    if [ "$n" -gt 0 ]; then ok "[files-13] image thumbnails are made ($n)"; else fail "[files-13] no thumbnails in ~/.cache/thumbnails"; fi
    # View keys, each undone again (the list must look as before).
    view_key() {
        local tag=$1 what=$2 on=$3 off=$4 box=${5:-$WX $WY $((WX + 857)) $((WY + 465))} d1 d2
        shot F-view-before > /dev/null
        ctl key $on
        sleep 2
        shot "F-$tag" > /dev/null
        ctl key $off
        sleep 2
        shot F-view-after > /dev/null
        d1=$(changed F-view-before "F-$tag" $box)
        d2=$(changed F-view-before F-view-after $box)
        if gt "$d1" 0.01 && gt 0.005 "$d2"; then ok "[$tag] $what (changed $d1, then back)"; else fail "[$tag] $what: changed $d1, after undoing $d2"; fi
    }
    ctl key home                             # the first screenshot
    view_key files-14 "Space shows the gallery, Escape closes it" spc esc "0 0 1280 800"
    view_key files-15 "Ctrl+Space shows the details pane" ctrl-spc ctrl-spc
    view_key files-17 "Ctrl+2 grid view, Ctrl+1 list view" ctrl-2 ctrl-1
    view_key files-16 "Ctrl+= zooms in, Ctrl+0 resets" ctrl-equal ctrl-0

    acc_usb
    ctl key meta_l-q
    sleep 2
}

acc_usb() {
    # A 16 MB FAT stick with one file, plugged into the VM's USB controller.
    if ! command -v mkfs.vfat > /dev/null || ! command -v mcopy > /dev/null; then
        say "  no mkfs.vfat/mcopy on the host: USB stick not tried"
        return
    fi
    rm -f "$W/usb.img"
    mkfs.vfat -n TESTSTICK -C "$W/usb.img" 16384 > /dev/null &&
        echo "on the stick" > "$W/on-stick.txt" && mcopy -i "$W/usb.img" "$W/on-stick.txt" ::/on-stick.txt
    # With the standard folders (xdg-user-dirs) the sidebar is longer than the
    # window: scroll it to the end, where the drives are listed.
    ctl scroll $((WX + 150)) $((WY + 300)) down 15
    sleep 1
    shot F-before-usb > /dev/null
    ctl usb plug "$W/usb.img"
    sleep 8
    ctl scroll $((WX + 150)) $((WY + 300)) down 15
    sleep 1
    shot F-usb > /dev/null
    check "the kernel sees the stick" g sh -c 'lsblk -no LABEL | grep -qx TESTSTICK'
    box=$(ctl bbox "$OUT/F-before-usb.ppm" "$OUT/F-usb.ppm" $((WX + 19)) $((WY + 45)) $((WX + 270)) $((WY + 455)))
    if [ "$box" = none ]; then
        if g test -x /usr/libexec/udisks2/udisksd; then
            fail "[files-28] the USB stick does not appear in Files"
        else
            known_issue "[files-28] the USB stick does not appear in Files: udisks2 and gvfs not installed (newer builds of the package recommend it)"
        fi
    else
        set -- $box
        ctl click $((WX + 93)) $(( $4 - 6 ))     # the new sidebar row
        sleep 4
        shot F-usb-open > /dev/null
        if g sh -c 'findmnt -rno TARGET -S LABEL=TESTSTICK | grep -q .' &&
           g sh -c 'test "$(cat /media/tester/TESTSTICK/on-stick.txt)" = "on the stick"'; then
            ok "[files-28] the USB stick appears in Files and mounts on a click"
            ctl click $((WX + 266)) $(( $4 - 6 ))    # eject, at the end of the row
            sleep 4
            if g sh -c 'findmnt -rno TARGET -S LABEL=TESTSTICK | grep -q .'; then fail "[files-28] eject did not unmount the stick"; else ok "[files-28] eject unmounts it"; fi
        else
            fail "[files-28] clicking the USB stick did not mount it (F-usb-open.png)"
        fi
    fi
    ctl usb unplug
}

acc_portal() {
    say "== desktop portal checklist: screenshots (xdg-desktop-portal-cosmic TESTING.md) [$(elapsed)]"
    local out
    out=$(gs cosmic-randr list --kdl 2>&1 | sed -n 's/^output "\([^"]*\)".*/\1/p' | head -n 1)
    take() {
        ctl key print
        sleep 3
        shot "$1" > /dev/null
        ctl key ret
        sleep 4
    }
    gs cosmic-randr mode --scale 1.5 "$out" 1280 800 > /dev/null 2>&1
    sleep 4
    take S-scale-150
    size=$(newest_png_size)
    check "[portal-1a,1c] at 150% scaling a screenshot is taken and saved ($size)" test "$size" = 1280x800
    case "$(gs timeout 5 wl-paste --list-types 2>&1)" in
        *image/png*) ok "[portal-1d] the screenshot is on the clipboard" ;;
        *) fail "[portal-1d] the screenshot is not on the clipboard" ;;
    esac
    gs cosmic-randr mode --scale 1 "$out" 1280 800 > /dev/null 2>&1
    gs cosmic-randr mode --transform rotate90 "$out" 1280 800 > /dev/null 2>&1
    sleep 4
    take S-rotated
    size=$(newest_png_size)
    check "[portal-1b] on a rotated screen the screenshot is upright ($size)" test "$size" = 800x1280
    gs cosmic-randr mode --transform normal "$out" 1280 800 > /dev/null 2>&1
    sleep 4
    shot S-normal-again 0.9
}

acc_player() {
    say "== COSMIC Media Player: plays sound (cosmic-player; Fedora's \"working sound\") [$(elapsed)]"
    g python3 -c '
import math, struct, wave
w = wave.open("/home/tester/tone.wav", "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(44100 * 20)))'
    gs sh -c 'setsid cosmic-player /home/tester/tone.wav < /dev/null > /tmp/player.log 2>&1 &'
    sleep 8
    shot M-player > /dev/null
    if gs wpctl status 2>&1 | sed -n '/Streams:/,/^$/p' | grep -q cosmic-player; then
        ok "[player] cosmic-player plays a sound file to the audio output"
    else
        fail "[player] no cosmic-player audio stream ($(g tail -n 3 /tmp/player.log | tr '\n' ' '))"
    fi
    ctl key meta_l-q
    wait_gone 10 "cosmic-player closed" pgrep -u tester -x cosmic-player || g pkill -x cosmic-player
}

acceptance() {
    acc_edit
    acc_launcher
    acc_osd
    acc_files
    acc_portal
    acc_player
    # Close what is left: the terminal on workspace 2 and the editor on 1.
    ctl key meta_l-2
    sleep 2
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
    ctl key meta_l-q
    sleep 2
}
