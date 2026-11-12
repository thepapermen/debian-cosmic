# Acceptance checklists

COSMIC's own regression checklists (the `TESTING.md` files of the epoch-1.11.0
components), item by item, with how this repository covers each one. Upstream
has no automated session tests; these lists are what its QA works through by
hand. Later sections will add what Fedora's release criteria, openSUSE's and
GNOME's openQA suites check that these lists do not.

Status:

- **auto**: checked by `vm-session.sh` / `acceptance.sh` in the VM; the tag in
  brackets (e.g. `[launcher-4]`) is what its report line starts with
- **known**: automated, and currently reported as a known issue
- **hardware**: needs real hardware (on the laptop, by hand)
- **manual**: visual or judgement call, by hand
- **planned**: can be automated in the VM, not done yet
- **n/a**: does not apply to this package

## cosmic-launcher

| # | Item | Status |
|---|---|---|
| 1 | Launcher does not flicker or jump when opening | manual |
| 2 | Cut text from the launcher, close it; pasting into an app works | auto `[launcher-2]` |
| 3 | All windows on all workspaces appear on launch | auto `[launcher-3,4,7,8]`: a window on workspace 2 is listed from workspace 1 |
| 4 | Choosing an app on another workspace moves workspaces and focus to it | auto `[launcher-3,4,7,8]` (the typed command lands in that window) |
| 5 | Launching an application works | auto (vm-session: "text editor", "shop", "power") |
| 6 | Typing text and removing it re-shows the open windows | auto `[launcher-6]` |
| 7 | Search works for applications and windows | auto `[launcher-3,4,7,8]`, `[launcher-13]` |
| 8 | Open windows are sorted above applications | auto `[launcher-3,4,7,8]` (Enter on the first result is the window) |
| 9 | Search works for COSMIC settings panels | auto `[launcher-9]` ("power") |
| 10 | `t:` executes a command in a terminal | auto `[launcher-10]` |
| 11 | `:` executes a command in sh | auto `[launcher-11]` |
| 12 | `=` calculates an equation | auto `[launcher-12]` (needs qalc: the package depends on it) |
| 13 | Search results: `cal` gives LibreOffice Calc, `pops` Popsicle, `shop` the Store | auto `[launcher-13]` for `shop`; the others n/a (not installed; Popsicle is Pop!_OS only) |

## cosmic-osd

| # | Item | Status |
|---|---|---|
| 1 | Volume hotkeys work | auto (vm-session: volume keys, popup) |
| 2 | Headset in a combo jack prompts for the type | hardware |
| 3 | Screen brightness hotkeys in 5% steps, down to 1% | hardware (no backlight in the VM) |
| 4 | Keyboard backlight hotkeys | hardware |
| 5 | Airplane mode hotkey | hardware (no radios in the VM) |
| 6 | Touchpad hotkey | hardware |
| 7 | Log Out dialog: Tab navigates the buttons | auto `[osd-7]` |
| 8 | Space on Cancel exits the dialog | known `[osd-8]`: Space does nothing (Enter and Escape work); not confirmed upstream |
| 9 | Escape exits the dialog | auto `[osd-9]` |

## xdg-desktop-portal-cosmic

| # | Item | Status |
|---|---|---|
| 1 | Screenshots work | auto (vm-session: Print Screen) |
| 1a | GUI works with 100% and non-100% scaling | auto `[portal-1a,1c]` at 150% |
| 1b | Rotated screen: GUI correct, screenshot correctly oriented | auto `[portal-1b]` (image is 800x1280); GUI by screenshot only |
| 1c | Screenshot files are saved | auto |
| 1d | Latest screenshot is copied to the clipboard | auto `[portal-1d]` |
| 2 | PipeWire screen capture (OBS) with the portal prompt | planned (ScreenCast portal from a small client) |
| 3 | Webcam and screen sharing prompted through Firefox | hardware/manual (webcam; Firefox not installed) |
| 4 | File chooser from Firefox | auto in part: the portal's FileChooser (vm-session); Firefox itself manual |
| 5 | File chooser, webcam, screen share from the Slack flatpak | n/a |

## cosmic-edit

| # | Item | Status |
|---|---|---|
| 1-3 | Three lines; copy the last two; paste at the end of the third (four lines) | auto `[edit-1,2,3]` |
| 4-9 | Undo, Enter, paste, undo, redo, save (five lines) | auto `[edit-4..9]` |
| 10-14 | Find a match, exit Find, cut it, paste on a new line, re-save (six lines) | auto `[edit-10..14]`; one Escape, not two (since 1.11.0 text inputs no longer capture Escape; a second one drops the selection) |
| 15-18, 21 | Line wrapping, word wrap off/on, horizontal scrolling, drag-select past the edge | manual |
| 19 | Reopen the file from the recents list | planned |
| 20 | Reopen the file through the Open dialog | auto `[edit-20]` |
| S1-S3 | View > Settings; Appearance settings; Vim bindings | planned |
| P1-P5 | Projects and Git management | planned (local Git repository) |

## cosmic-files

| # | Item | Status |
|---|---|---|
| 1 | Middle-click opens a directory in a new, unfocused tab | planned |
| 2 | Two scrollable tabs scroll independently | manual |
| 3 | No stale hover highlight after scrolling | manual |
| 4 | Right-click in the sidebar changes nothing else | manual |
| 5 | Remove a sidebar item and pin it again | planned |
| 6 | New folder, then enter it | auto `[files-6]`, `[files-6,24]` |
| 7 | New file in an empty folder (right-click) | auto `[files-7]` |
| 8 | Drag a new file into the folder | planned (copy and paste covered, `[files-6,24]`) |
| 9 | Rename | auto `[files-9]` (F2) |
| 10 | Open with a non-default app; browse the Store for apps | manual |
| 11 | Move to trash | auto `[files-11]` (Delete key; the menu entry by hand) |
| 12 | Permanently delete (Shift) | auto `[files-12]` (Shift+Delete, with the confirmation) |
| 13 | Image and video thumbnails | auto `[files-13]` (images) |
| 14 | Gallery preview with Space | auto `[files-14]` |
| 15 | Details pane with Ctrl+Space | auto `[files-15]` |
| 16 | Zoom in/out, reset | auto `[files-16]` |
| 17 | Ctrl+1 / Ctrl+2 list and icon view | auto `[files-17]` |
| 18 | Ctrl+H shows/hides hidden files | auto `[files-18]` |
| 19-23 | Folders first/inline; Theme; Type to Search; single-click; sorting | planned |
| 24 | Cut, copy and paste files | auto `[files-6,24]` (copy; cut planned) |
| 25 | F5 reloads | planned |
| 26 | Sidebar collapses and expands | manual |
| 27 | Network drive (SFTP) | planned (the VM's own sshd; needs gvfs-backends) |
| 28 | USB drive: mount, browse, eject | auto `[files-28]` (needs udisks2 and gvfs: recommended) |
| 29 | Desktop icons | planned |
| 30 | Drag and drop into Firefox | manual |

## cosmic-settings

| Page | Item | Status |
|---|---|---|
| Wi-Fi | Disconnect and connect | hardware |
| Bluetooth | Connect; disconnect and reconnect; forget and pair again | hardware |
| Wallpaper | A click switches at once; stays after leaving the page | planned |
| Appearance | Dark/light: COSMIC apps at once, GNOME apps after restart | auto in part (vm-session: the setting's file, portal value, panel); the page itself planned |
| Appearance | Accent colour; roundness; interface density | planned |
| Panel / Dock | Auto-hide with tiling and with a maximized window | planned |
| Dock | Position on screen; style settings | planned |
| Displays | Second display: arrange by dragging; mirroring | planned (two virtual outputs) |
| Sound | Volume, balance, amplification, profiles, per-app streams | planned in part (streams: `[player]` plays one); devices hardware |
| Power & battery | Changing the power mode takes effect, the panel applet shows it | auto `[settings-power]` (power-saver and balanced; the VM has no performance profile) |
| Touchpad | Click and scroll settings | hardware |
| Default apps | Changing the default terminal changes Super+T | planned |
| X11 apps | Global shortcuts in X11 apps | manual |
| Date & time | Time zone | auto (vm-session: the first-login wizard sets it) |
| Date & time | 24-hour time in Settings, panel and lock screen; seconds; first day of week; date in the applet | planned |
| About | Changing the hostname | planned |

## cosmic-store

| Item | Status |
|---|---|
| Install and remove a Flatpak app; remove and re-add Flatpak sources | planned (flatpak is suggested only) |
| Install and remove a Deb app; install Deb updates | planned (PackageKit is suggested only) |
| Search; categories | planned |

## cosmic-player

| Item | Status |
|---|---|
| Plays a media file (not on upstream's list; Fedora's "working sound") | auto `[player]` |
| Open media folder; select media; recent media | planned |
| A-B repeat; frame stepping; navigation keys | manual |

## Found with these lists

- The launcher's `=` needs `qalc` and its file search `fdfind`: upstream's
  pop-launcher package depends on both; this package now does too.
- A USB stick does not appear in COSMIC Files without udisks2 and gvfs; now
  recommended (with gvfs-fuse and xdg-user-dirs, as Pop!_OS has them).
- Space on the log out dialog's Cancel does nothing (Enter and Escape work).
- Settings' Power page does not follow a power mode changed in the panel
  applet while it is open (the reverse works, as the list asks).
- COSMIC offers "High performance" even when power-profiles-daemon has no
  such profile (in the VM); choosing it fails silently.
