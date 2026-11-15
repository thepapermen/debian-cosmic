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

# pick NAME SHOT: in the file chooser (the portal's) that has just opened,
# choose the file or folder NAME (unique under home) and press Open. The
# dialog opens beside its parent window (they cascade), and remembers
# whether its search bar was shown: so it is found on the screen, and NAME
# is typed (typing searches the folder and its subfolders), its one result
# selected (the first click on a row is sometimes taken only as focus:
# twice) and Open pressed (from the bottom right corner). WX WY are kept.
pick() {
    local x0 y0 x1 y1 wx=$WX wy=$WY
    shot "$2" > /dev/null
    set -- "$1" "$2" $(ctl winbox "$OUT/$2.ppm" 600 300)
    if [ "$3" = none ]; then say "  ($2: no file chooser found)"; return 1; fi
    x0=$3 y0=$4 x1=$5 y1=$6
    ctl type "$1"
    sleep 5
    shot "$2-found" > /dev/null
    ctl click $((x0 + 152)) $((y0 + 172)); sleep 1
    ctl click $((x0 + 152)) $((y0 + 172)); sleep 1
    ctl click $((x1 - 57)) $((y1 - 35))      # Open
    WX=$wx WY=$wy
}

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

# The rest of cosmic-edit TESTING.md: 19 (reopen from the recents list),
# Settings (Appearance; Vim bindings), Projects & Git management (a local
# repository: open it as a project, find in project, a change staged in Git
# management, another change shows while it is open). Edit's settings are
# backed up and put back; git is installed for the test and purged after.
acc_edit_more() {
    say "== COSMIC Text Editor: recents, settings (appearance, Vim), project search, Git management (cosmic-edit TESTING.md) [$(elapsed)]"
    local cfg=/home/tester/.config/cosmic/com.system76.CosmicEdit text
    if ! g sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git > /dev/null 2>&1; then
        fail "[edit-git] could not install git"
        return
    fi
    cfg_save com.system76.CosmicEdit
    g sh -c 'mkdir -p ~/ed && printf "alpha\nbeta\ngamma\n" > ~/ed/notes.txt'
    g sh -c 'mkdir -p ~/vmtest-proj && cd ~/vmtest-proj && git init -q && printf "first line\nneedle here\n" > a.txt && printf "other\n" > b.txt && git add . && git -c user.name=vmtest -c user.email=vmtest@localhost commit -qm init'

    # 19: open the file, close the editor, open it from the recents list.
    gs sh -c 'setsid cosmic-edit /home/tester/ed/notes.txt < /dev/null > /dev/null 2>&1 &'
    wait_for 15 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 3
    ctl key meta_l-q
    wait_gone 10 "cosmic-edit closed" pgrep -u tester -x cosmic-edit
    gs sh -c 'setsid cosmic-edit < /dev/null > /tmp/edit-more.log 2>&1 &'
    wait_for 15 "cosmic-edit running" pgrep -u tester -x cosmic-edit
    sleep 3
    win ED0
    wclick 85 26; sleep 2                     # File
    ctl move $((WX + 132)) $((WY + 167)); sleep 2      # Open recent file (opens on hover)
    ctl move $((WX + 389)) $((WY + 167)); sleep 0.5
    wclick 445 167; sleep 3                   # the newest: ~/ed/notes.txt
    ctl key ctrl-a; ctl key ctrl-c; sleep 0.5
    text=$(gs wl-paste -n 2> /dev/null | tr '\n' '|')
    check "[edit-19] the recents list reopens the file ($text)" test "$text" = "alpha|beta|gamma|"

    # Settings: font size, theme, Vim bindings.
    wclick 192 26; sleep 1; wclick 214 313; sleep 2    # View > Settings...
    shot ED1-settings > /dev/null
    wclick 746 383; sleep 1; wclick 746 241; sleep 2   # Default font size: 10px
    shot ED2-10px > /dev/null
    check "[edit-S2] the font size setting changes the text" gt "$(changed ED1-settings ED2-10px $((WX + 19)) $((WY + 80)) $((WX + 344)) $((WY + 165)))" 0.05
    # (The theme list hangs from the button's left edge; x 754 is inside it.)
    wclick 726 184; sleep 1; wclick 754 297; sleep 2   # Theme: Light
    shot ED3-light > /dev/null
    check "[edit-S2] the theme setting turns the editor light" gt "$(changed ED2-10px ED3-light $((WX + 19)) $((WY + 145)) $((WX + 344)) $((WY + 445)))" 0.5
    wclick 726 184; sleep 1; wclick 754 225; sleep 2   # Theme: Match desktop
    ctl scroll $((WX + 606)) $((WY + 335)) down 10; sleep 1
    wclick 766 398; sleep 1                   # Enable Vim bindings
    wclick 289 113; sleep 1                   # into the text
    ctl key esc
    ctl type "gg"
    ctl type "dd"
    sleep 1
    ctl key ctrl-s
    sleep 2
    text=$(g sh -c 'tr "\n" "|" < ~/ed/notes.txt')
    case $text in
        "beta|gamma|") ok "[edit-S3] Vim bindings: dd deletes the line" ;;
        "|beta|gamma|") known_issue "[edit-S3] Vim bindings: dd empties the line but leaves it (pop-os/cosmic-edit#445, open)" ;;
        *) fail "[edit-S3] Vim bindings: gg dd gave \"$text\"" ;;
    esac
    ctl type "u"
    sleep 1
    ctl key ctrl-s
    sleep 2
    check "[edit-S3] Vim bindings: u undoes it" test "$(g sh -c 'tr "\n" "|" < ~/ed/notes.txt')" = "alpha|beta|gamma|"
    wclick 766 398; sleep 1                   # Vim bindings off
    wclick 769 90; sleep 2                    # Close (settings)

    # Projects & Git management.
    shot PJ0-open-project > /dev/null
    ctl key ctrl-shift-o
    sleep 3
    pick vmtest-proj PJ0-chooser || fail "[edit-P1] Open project showed no folder chooser"
    sleep 4
    ctl key ctrl-shift-f; sleep 2             # Find in project...
    ctl type "needle"
    ctl key ret
    sleep 3
    shot PJ1-find > /dev/null
    if gt "$(changed PJ0-open-project PJ1-find $((WX + 503)) $((WY + 180)) $((WX + 831)) $((WY + 265)))" 0.05; then
        ok "[edit-P2] Find in project lists the match in a.txt"
    else
        fail "[edit-P2] Find in project found nothing (PJ1-find.png)"
    fi
    wclick 614 239; sleep 2                   # the result: opens a.txt
    wclick 289 113; ctl key home              # (a click puts the keyboard in the text)
    ctl type "CHANGED "
    ctl key ctrl-s
    sleep 2
    ctl key ctrl-shift-g; sleep 3             # Git management
    shot PJ2-git > /dev/null
    wclick 767 288; sleep 3                   # Stage (a.txt)
    check "[edit-P4] Git management stages the change (git: $(g sh -c 'cd ~/vmtest-proj && git status --short | tr "\n" " "'))" \
        test "$(g sh -c 'cd ~/vmtest-proj && git status --short')" = "M  a.txt"
    shot PJ3-staged > /dev/null
    wclick 93 136; sleep 2                    # b.txt (project sidebar)
    wclick 289 93; ctl key end
    ctl type " more"
    ctl key ctrl-s
    sleep 4
    shot PJ4-second-change > /dev/null
    if [ "$(g sh -c 'cd ~/vmtest-proj && git status --short | tr "\n" " "')" = "M  a.txt  M b.txt " ] &&
       gt "$(changed PJ3-staged PJ4-second-change $((WX + 519)) $((WY + 260)) $((WX + 831)) $((WY + 420)))" 0.05; then
        ok "[edit-P5] a change made while Git management is open shows there (b.txt unstaged)"
    else
        fail "[edit-P5] Git management did not show the new change (PJ4-second-change.png)"
    fi
    ctl key ctrl-q
    wait_gone 10 "cosmic-edit closed" pgrep -u tester -x cosmic-edit || g pkill -u tester -x cosmic-edit
    cfg_restore com.system76.CosmicEdit
    g rm -r /home/tester/ed /home/tester/vmtest-proj
    g sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --autoremove git > /dev/null 2>&1
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
        "= qalc command is not installed"*)
                 ok "[launcher-2] text cut in the launcher can be pasted after it closed"
                 known_issue "[launcher-12] = needs qalc, not installed (newer builds of the package depend on it)" ;;
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
    if wait_for 20 "the command in a terminal" test -e /tmp/launcher-t; then
        ok "[launcher-10] t: runs a command in a terminal"
    else
        # Once in CI (run 43743599853) nothing started and nothing was
        # logged; it passed in every other run. Keep the evidence, try again.
        shot LT10-missed > /dev/null
        local term
        term=$(g pgrep -u tester -x cosmic-term | tr '\n' ' ')
        ctl key esc
        sleep 2
        ctl key meta_l
        sleep 3
        ctl type "t: touch /tmp/launcher-t"
        sleep 2
        ctl key ret
        if wait_for 20 "the command in a terminal (again)" test -e /tmp/launcher-t; then
            known_issue "[launcher-10] the first t: command did not run, the second did (LT10-missed.png; cosmic-term then: ${term:-none})"
        else
            shot LT10-failed > /dev/null
            fail "[launcher-10] t: did not run the command in a terminal (LT10-missed.png, LT10-failed.png)"
        fi
    fi
    sleep 2
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
    if wait_for 20 "cosmic-settings running" pgrep -u tester -f '^(/usr/bin/)?cosmic-settings( |$)' &&
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

# The rest of cosmic-files TESTING.md: 1 (middle-click: a new tab behind),
# 5 (remove a sidebar item, pin it again), 8 (drag a file into a folder),
# 19-23 (folders first, theme, type to search, single click, sorting),
# 24 (cut), 25 (F5), 29 (desktop icons). The order of the rows is read with
# Home/End and Ctrl+C (the clipboard gets the selected file's path).
acc_files_more() {
    say "== COSMIC Files: tabs, sidebar, drag, sorting, folders first, type to search, single click, theme, cut, F5, desktop icons (cosmic-files TESTING.md) [$(elapsed)]"
    local cfg=/home/tester/.config/cosmic/com.system76.CosmicFiles/v1 text
    local fav=$cfg/favorites
    # first_last: "FIRST..LAST" of the rows shown.
    first_last() {
        local f l
        ctl key home; ctl key ctrl-c; sleep 0.5; f=$(gs wl-paste -n 2> /dev/null | sed 's|.*/||')
        ctl key end; ctl key ctrl-c; sleep 0.5; l=$(gs wl-paste -n 2> /dev/null | sed 's|.*/||')
        echo "$f..$l"
    }
    g sh -c 'mkdir -p ~/fm/a-dir ~/fm/Z-dir && echo inner > ~/fm/a-dir/inner.txt && echo bb > ~/fm/b-file.txt && echo c > ~/fm/c-file.txt && head -c 5000 /dev/zero > ~/fm/d-big.bin'
    # Files' settings, put back at the end (sort order, theme, sidebar).
    cfg_save com.system76.CosmicFiles
    gs sh -c 'setsid cosmic-files /home/tester/fm < /dev/null > /tmp/files-fm.log 2>&1 &'
    wait_for 15 "cosmic-files running" pgrep -u tester -x cosmic-files
    sleep 3
    win FM0
    wclick 249 26; sleep 1; wclick 275 58; sleep 2      # Sort: A-Z
    wclick 400 120                            # a-dir: select a row
    check "[files-19,23] A-Z with folders first: a-dir first, d-big.bin last" test "$(first_last)" = "a-dir..d-big.bin"
    wclick 249 26; sleep 1; wclick 275 94; sleep 2      # Sort: Z-A
    check "[files-23] Z-A: Z-dir first, b-file.txt last" test "$(first_last)" = "Z-dir..b-file.txt"
    wclick 249 26; sleep 1; wclick 326 238; sleep 2     # Sort: largest to smallest
    check "[files-23] largest to smallest: the 2-byte c-file.txt last" test "$(first_last | sed 's/.*\.\.//')" = c-file.txt
    wclick 249 26; sleep 1; wclick 275 58; sleep 2      # Sort: A-Z
    wclick 192 26; sleep 1; wclick 269 276; sleep 2     # View: List directories first (off)
    check "[files-19] folders not first: Z-dir sorts among the files (last)" test "$(first_last)" = "a-dir..Z-dir"
    wclick 192 26; sleep 1; wclick 269 276; sleep 2     # (on again)
    check "[files-19] folders first again" test "$(first_last)" = "a-dir..d-big.bin"

    # 21: typing searches this folder and its subfolders.
    ctl type "inner"
    sleep 3
    shot FM1-search > /dev/null
    wclick 400 120
    ctl key ctrl-a; ctl key ctrl-c; sleep 0.5
    check "[files-21] typing searches, subfolders too (\"inner\" finds a-dir/inner.txt)" test "$(gs wl-paste -n 2> /dev/null)" = /home/tester/fm/a-dir/inner.txt
    ctl key esc; sleep 1; ctl key esc; sleep 2

    # 1: middle-click a folder: a new tab, behind the current one.
    shot FM2-no-tabs > /dev/null
    wclick 400 120 middle
    sleep 2
    shot FM3-tab > /dev/null
    if gt "$(changed FM2-no-tabs FM3-tab $((WX + 315)) $((WY + 51)) $((WX + 831)) $((WY + 83)))" 0.1 && [ "$(first_last)" = "a-dir..d-big.bin" ]; then
        ok "[files-1] middle-click on a folder opens it in a new tab and stays in the current one"
    else
        fail "[files-1] middle-click did not open a background tab (FM3-tab.png)"
    fi
    wclick 814 66                             # the new tab's close button
    sleep 2

    # 24: cut b-file.txt, paste it into a-dir.
    wclick 400 250                            # b-file.txt (rows: a-dir, Z-dir, b-file...)
    ctl key ctrl-x
    wclick 400 120; ctl key ret; sleep 2      # into a-dir
    ctl key ctrl-v
    if wait_for 10 "b-file.txt moved" sh -c 'test -e ~/fm/a-dir/b-file.txt -a ! -e ~/fm/b-file.txt'; then
        ok "[files-24] cut and paste moves a file"
    else
        fail "[files-24] cut and paste did not move b-file.txt into a-dir"
    fi
    ctl key alt-left; sleep 2                 # back to fm

    # 8: drag c-file.txt onto Z-dir (rows now: a-dir, Z-dir, c-file, d-big).
    ctl drag $((WX + 400)) $((WY + 250)) $((WX + 400)) $((WY + 185))
    if wait_for 10 "c-file.txt moved" sh -c 'test -e ~/fm/Z-dir/c-file.txt -a ! -e ~/fm/c-file.txt'; then
        ok "[files-8] dragging a file onto a folder moves it there"
    else
        fail "[files-8] dragging c-file.txt onto Z-dir did not move it"
    fi

    # 25: a file made outside Files, then F5.
    g sh -c 'echo e > ~/fm/e-new.txt'
    ctl key f5
    sleep 2
    wclick 400 120
    ctl key ctrl-a; ctl key ctrl-c; sleep 0.5
    text=$(gs wl-paste -n 2> /dev/null)
    case $text in *e-new.txt*) ok "[files-25] after F5 the folder lists a file made meanwhile" ;;
                  *) fail "[files-25] after F5 the folder does not list e-new.txt" ;; esac

    # 22: single click opens; 20: the theme.
    ctl key ctrl-comma; sleep 2
    ctl scroll $((WX + 606)) $((WY + 335)) down 5; sleep 1
    wclick 766 349; sleep 1                   # Single click to open: on
    wclick 769 90; sleep 2                    # Close (settings)
    wclick 400 120; sleep 2                   # one click on a-dir
    text=$(first_last)
    check "[files-22] with single click to open, one click opens a folder (a-dir: $text)" test "${text%%..*}" = b-file.txt
    ctl key alt-left; sleep 2
    ctl key ctrl-comma; sleep 2
    ctl scroll $((WX + 606)) $((WY + 335)) down 5; sleep 1
    wclick 766 349; sleep 1                   # (off again)
    ctl scroll $((WX + 606)) $((WY + 335)) up 5; sleep 1
    shot FM4-dark > /dev/null
    # (The list hangs from the button's left edge, which moves with its
    # text: x 754 is inside it either way.)
    wclick 726 184; sleep 1; wclick 754 297; sleep 2   # Theme: Light
    shot FM5-light > /dev/null
    check "[files-20] Theme Light turns the window light" gt "$(changed FM4-dark FM5-light $((WX + 10)) $((WY + 50)) $((WX + 350)) $((WY + 450)))" 0.5
    wclick 726 184; sleep 1; wclick 754 225; sleep 2   # Theme: Match desktop
    shot FM6-back > /dev/null
    check "[files-20] Match desktop brings the dark theme back" lt "$(changed FM4-dark FM6-back $((WX + 10)) $((WY + 50)) $((WX + 350)) $((WY + 450)))" 0.05
    wclick 769 90; sleep 2

    # 5: remove Music from the sidebar, pin it again (Ctrl+D on it in Home).
    wclick 78 234 right; sleep 2
    ctl click $((WX + 78 + 86)) $((WY + 234 + 165)); sleep 2     # Remove from sidebar
    if g sh -c "grep -q Music '$fav'"; then fail "[files-5] Remove from sidebar left Music in the favourites"; else ok "[files-5] Remove from sidebar removes Music"; fi
    ctl key ctrl-l; sleep 1; ctl key ctrl-a
    ctl type "/home/tester"; ctl key ret; sleep 3
    ctl type "Mus"; sleep 3
    wclick 400 120; sleep 1
    ctl key ctrl-d; sleep 2
    check "[files-5] Ctrl+D (Add to sidebar) pins Music again" g sh -c "grep -q Music '$fav'"
    ctl key esc; sleep 1
    ctl key meta_l-q
    wait_gone 10 "cosmic-files closed" pgrep -u tester -x cosmic-files || g pkill -u tester -x cosmic-files
    # Files' settings as before (later checks click the sidebar by position).
    cfg_restore com.system76.CosmicFiles

    # 29: desktop icons (cosmic-files-applet shows ~/Desktop).
    ctl click 640 400; sleep 1
    shot FM7-desktop > /dev/null
    g sh -c 'echo hi > ~/Desktop/desktop-test.txt'
    local i
    for i in 1 2 3 4 5; do                   # (up to 15 s on a busy VM)
        sleep 3
        shot FM8-desktop-icon > /dev/null
        gt "$(changed FM7-desktop FM8-desktop-icon 0 40 300 200)" 0.05 && break
    done
    if gt "$(changed FM7-desktop FM8-desktop-icon 0 40 300 200)" 0.05; then
        ok "[files-29] a file in ~/Desktop shows as a desktop icon"
        ctl click 66 85; sleep 1; ctl key ret
        if wait_for 10 "the file opened" pgrep -u tester -f "cosmic-edit /home/tester/Desktop/desktop-test.txt"; then
            ok "[files-29] Enter on the desktop icon opens the file (COSMIC Edit)"
            ctl key meta_l-q; sleep 2
        else
            fail "[files-29] Enter on the desktop icon did not open the file"
        fi
    else
        fail "[files-29] no desktop icon for ~/Desktop/desktop-test.txt (FM8-desktop-icon.png)"
    fi
    g rm -f /home/tester/Desktop/desktop-test.txt
    for i in 1 2 3 4 5; do
        sleep 3
        shot FM9-desktop-empty > /dev/null
        lt "$(changed FM7-desktop FM9-desktop-empty 0 40 300 200)" 0.01 && break
    done
    check "[files-29] the icon goes with the file" lt "$(changed FM7-desktop FM9-desktop-empty 0 40 300 200)" 0.01
    g rm -r /home/tester/fm
}

# cosmic-files TESTING.md 27: a network drive (SFTP, through gvfs-backends,
# which the package recommends). The server is the VM's own sshd; the cloud
# image takes keys only, so password logins from localhost are allowed for
# the test and the drop-in is removed afterwards.
acc_files_network() {
    say "== COSMIC Files: a network drive over SFTP: connect with a password, list, copy, eject (cosmic-files TESTING.md) [$(elapsed)]"
    local conf=/etc/ssh/sshd_config.d/90-vmtest-sftp.conf
    g sh -c 'mkdir -p ~/sftp-share && echo remote-file > ~/sftp-share/hello-sftp.txt && rm -f ~/Downloads/hello-sftp.txt'
    g sudo sh -c "printf 'Match Address 127.0.0.1,::1\n    PasswordAuthentication yes\n    KbdInteractiveAuthentication yes\n' > $conf && sshd -t && systemctl reload ssh"
    gs sh -c 'setsid cosmic-files < /dev/null > /tmp/files-net.log 2>&1 &'
    wait_for 15 "cosmic-files running" pgrep -u tester -x cosmic-files
    sleep 3
    win NW0
    wclick 90 412                             # Networks (sidebar)
    sleep 3
    wclick 758 430                            # Add network drive
    sleep 3
    wclick 607 148                            # the server address
    sleep 1
    ctl type "sftp://tester@localhost/home/tester/sftp-share"
    ctl key ret
    sleep 5
    shot NW1-password > /dev/null
    if gt "$(changed NW0 NW1-password $((WX + 144)) $((WY + 103)) $((WX + 714)) $((WY + 363)))" 0.3; then
        ok "[files-27] connecting asks for the password"
        ctl type "$PASS"
        ctl key ret
    else
        fail "[files-27] no password prompt after Connect (NW1-password.png)"
    fi
    if wait_for 20 "the drive mounted" sh -c 'ls /run/user/1000/gvfs/ | grep -q "^sftp:host=localhost"'; then
        ok "[files-27] the SFTP drive is connected"
        ctl key ctrl-l
        sleep 1
        ctl key ctrl-a
        ctl type "sftp://tester@localhost/home/tester/sftp-share"
        ctl key ret
        sleep 4
        shot NW2-share > /dev/null
        wclick 572 335                        # empty space in the folder
        ctl key ctrl-a
        ctl key ctrl-c
        sleep 1
        case $(gs wl-paste -n 2> /dev/null) in
            *sftp-share/hello-sftp.txt*) ok "[files-27] the drive's folder lists its file" ;;
            *) fail "[files-27] the drive's folder does not list hello-sftp.txt (NW2-share.png)" ;;
        esac
        ctl key ctrl-l
        sleep 1
        ctl key ctrl-a
        ctl type "/home/tester/Downloads"
        ctl key ret
        sleep 3
        wclick 572 335
        ctl key ctrl-v
        if wait_for 15 "the file copied" grep -q remote-file /home/tester/Downloads/hello-sftp.txt; then
            ok "[files-27] a file copies from the drive to a local folder"
        else
            fail "[files-27] copying the drive's file to Downloads did not work"
        fi
        ctl scroll $((WX + 150)) $((WY + 335)) down 5
        sleep 1
        wclick 266 430                        # the drive's eject button (sidebar)
        sleep 3
        shot NW3-ejected > /dev/null
        if wait_for 10 "the drive ejected" sh -c '! ls /run/user/1000/gvfs/ | grep -q "^sftp:"'; then
            ok "[files-27] the sidebar's eject button disconnects the drive"
        else
            fail "[files-27] the drive is still connected after eject (NW3-ejected.png)"
            gs gio mount -u "sftp://tester@localhost/" > /dev/null 2>&1
        fi
    else
        fail "[files-27] the SFTP drive did not connect ($(g tail -n 2 /tmp/files-net.log | tr '\n' ' '))"
    fi
    ctl key meta_l-q
    wait_gone 10 "cosmic-files closed" pgrep -u tester -x cosmic-files || g pkill -u tester -x cosmic-files
    g sudo sh -c "rm -f $conf && systemctl reload ssh"
    g sh -c 'rm -f ~/sftp-share/hello-sftp.txt ~/Downloads/hello-sftp.txt && rmdir ~/sftp-share'
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
    shot S-before > /dev/null
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
    # Beside the dock (between it and the screen's edges) the wallpaper shows
    # as before the scale and rotation changes.
    local l r a b
    set -- $(ctl dock "$OUT/S-before.ppm")
    l=$(( $1 - 8 )) r=$(( $2 + 8 ))
    a=$(changed S-before S-normal-again 0 728 $l 796) b=$(changed S-before S-normal-again $r 728 1280 796)
    if lt "$a" 0.02 && lt "$b" 0.02; then
        ok "[portal] after the scale and rotation changes nothing stale is left beside the dock ($a $b)"
    else
        known_issue "[portal] after the scale and rotation changes, pixels of the dock as it was stay between the dock and the screen's edges (S-normal-again.png; $a $b): cosmic-panel#576, software rendering"
    fi
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
    # What reaches the output is the sound played (Fedora "working sound",
    # GNOME gnome_audio): what the output's monitor records must be the
    # 440 Hz tone.
    set -- $(output_tone)
    if [ "$1" -gt 300 ] && [ "$2" -ge 430 ] && [ "$2" -le 450 ]; then
        ok "[player] the output carries the sound played: the 440 Hz tone (recorded: ${2} Hz, level $1)"
    else
        fail "[player] the output's recording is not the tone played (level $1, ${2} Hz)"
    fi
    ctl key meta_l-q
    wait_gone 10 "cosmic-player closed" pgrep -u tester -x cosmic-player || g pkill -x cosmic-player
}

# output_tone: "LEVEL HZ" of two seconds recorded from the default output's
# monitor (the frequency from the zero crossings; "0 0" if nothing).
output_tone() {
    gs sh -c 'timeout 3 parecord -d @DEFAULT_MONITOR@ --rate=44100 --channels=1 --format=s16le --file-format=wav /tmp/rec.wav' > /dev/null 2>&1
    local rec
    rec=$(g python3 -c '
import struct, wave
w = wave.open("/tmp/rec.wav")
n = w.getnframes(); s = struct.unpack("<%dh" % n, w.readframes(n))
s = s[len(s) // 4:]                       # past the start of the recording
rms = (sum(x * x for x in s) / max(1, len(s))) ** 0.5
z = sum(1 for a, b in zip(s, s[1:]) if a < 0 <= b)
print("%d %d" % (rms, z * 44100 / max(1, len(s))))' 2> /dev/null)
    echo "${rec:-0 0}"
}

# The rest of cosmic-player TESTING.md (file operations): Open media folder
# shows the folder in the folder pane; a file chosen there plays (the tone
# recorded from the output); Open recent media lists it afterwards.
acc_player_files() {
    say "== COSMIC Media Player: a media folder, a file from it, recent media (cosmic-player TESTING.md) [$(elapsed)]"
    g sh -c 'mkdir -p ~/vmtest-media && cd ~/vmtest-media && python3 -c "
import math, struct, wave
for n, f in ((\"low\", 220), (\"high\", 880)):
    w = wave.open(n + \".wav\", \"wb\"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(b\"\".join(struct.pack(\"<h\", int(6000 * math.sin(2 * math.pi * f * i / 44100))) for i in range(44100 * 30)))
"'
    cfg_save com.system76.CosmicPlayer
    gs sh -c 'setsid cosmic-player < /dev/null > /tmp/player-files.log 2>&1 &'
    wait_for 15 "cosmic-player running" pgrep -u tester -x cosmic-player
    sleep 3
    win PF0
    wclick 85 26; sleep 2                    # File
    shot PF1-empty > /dev/null
    wclick 145 167; sleep 3                  # Open media folder...
    pick vmtest-media PF1-chooser || fail "[player-files] no folder chooser"
    sleep 4
    shot PF2-files > /dev/null               # the folder, open: high.wav, low.wav
    if gt "$(changed PF1-empty PF2-files "$WX" $((WY + 135)) $((WX + 283)) $((WY + 215)))" 0.02; then
        ok "[player-files] Open media folder shows the folder and its files in the folder pane"
    else
        fail "[player-files] the folder pane does not show the media folder's files (PF2-files.png)"
    fi
    wclick 72 154; sleep 5                   # high.wav
    set -- $(output_tone)
    if [ "$1" -gt 300 ] && [ "$2" -ge 860 ] && [ "$2" -le 900 ]; then
        ok "[player-files] a file chosen in the folder pane plays (880 Hz recorded)"
    else
        fail "[player-files] high.wav from the folder pane: recorded level $1, ${2} Hz"
    fi
    wclick 85 26; sleep 2                    # File
    ctl move $((WX + 141)) $((WY + 94)); sleep 2      # Open recent media (opens on hover)
    shot PF3-recent > /dev/null
    if gt "$(changed PF2-files PF3-recent $((WX + 383)) $((WY + 80)) $((WX + 720)) $((WY + 140)))" 0.05; then
        ok "[player-files] Open recent media lists the file played"
    else
        fail "[player-files] Open recent media lists nothing (PF3-recent.png)"
    fi
    ctl key esc; sleep 1
    ctl key meta_l-q
    wait_gone 10 "cosmic-player closed" pgrep -u tester -x cosmic-player || g pkill -x cosmic-player
    cfg_restore com.system76.CosmicPlayer
    g rm -r /home/tester/vmtest-media
}

acceptance() {
    acc_edit
    acc_launcher
    acc_osd
    acc_files
    acc_files_more
    acc_files_network
    acc_portal
    acc_player
    acc_player_files
    # Close what is left: the terminal on workspace 2 and the editor on 1.
    ctl key meta_l-2
    sleep 2
    ctl key meta_l-q
    sleep 2
    ctl key meta_l-1
    sleep 2
    ctl key meta_l-q
    sleep 2
    acc_edit_more            # after the editor above is closed
    # Nothing a failed check left open may get in the way of the next ones
    # (a file chooser left open took a tile in [wm]). Not cosmic-files-applet:
    # the desktop.
    local left
    left=$(g pgrep -u tester -f '^(/usr/bin/)?cosmic-(edit|player|files|store|settings)( |$)' | tr '\n' ' ')
    if [ -n "$left" ]; then
        say "  closing what the checks above left open: $(g ps -o comm= -p "$(echo $left | tr ' ' ,)" 2> /dev/null | tr '\n' ' ')"
        g pkill -u tester -f '^(/usr/bin/)?cosmic-(edit|player|files|store|settings)( |$)'
        sleep 3
    fi
}
