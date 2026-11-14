# Acceptance checklists

COSMIC's own regression checklists (the `TESTING.md` files of the epoch-1.11.0
components), item by item, with how this repository covers each one. Upstream
has no automated session tests; these lists are what its QA works through by
hand. The last sections add what Fedora's release criteria and the openQA
desktop suites of Fedora, openSUSE and GNOME check that these lists do not
(`criteria.sh`).

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
| Wallpaper | A click switches at once; stays after leaving the page | auto `[settings-wallpaper]` |
| Appearance | Dark/light: COSMIC apps at once, GNOME apps after restart | auto (vm-session: the setting's file, portal value, panel; `[settings-appearance]`: Light and Dark on the page) |
| Appearance | Accent colour; roundness; interface density | auto `[settings-appearance]` (accent: the window border changes at once, and back); roundness, density planned |
| Panel / Dock | Auto-hide with tiling and with a maximized window | planned |
| Dock | Position on screen; style settings | planned |
| Displays | Second display: arrange by dragging; mirroring | planned (two virtual outputs) |
| Sound | Volume, balance, amplification, profiles, per-app streams | planned in part (streams: `[player]` plays one); devices hardware |
| Power & battery | Changing the power mode takes effect, the panel applet shows it | auto `[settings-power]` (power-saver and balanced; the VM has no performance profile) |
| Touchpad | Click and scroll settings | hardware |
| Default apps | Changing the default terminal changes Super+T | auto `[settings-apps]` (to Zutty, when installed; then back) |
| X11 apps | Global shortcuts in X11 apps | manual |
| Date & time | Time zone | auto (vm-session: the first-login wizard sets it) |
| Date & time | 24-hour time in Settings, panel and lock screen | auto `[settings-time]` |
| Date & time | Seconds; first day of week; date in the applet | planned |
| About | Changing the hostname | known `[settings-about]`: does nothing on Debian (see below) |

## cosmic-store

| Item | Status |
|---|---|
| Install and remove a Flatpak app; remove and re-add Flatpak sources | planned (flatpak is suggested only) |
| Install and remove a Deb app; install Deb updates | auto `[store]` (a local repository, `local-repo.sh`: Check for updates, Update, search, Install, Open, Uninstall, each with the admin prompt; PackageKit and apt-config-icons are recommended from build 15) |
| Search; categories | auto `[store]` (search); categories planned |

## cosmic-player

| Item | Status |
|---|---|
| Plays a media file (not on upstream's list; Fedora's "working sound") | auto `[player]` |
| Open media folder; select media; recent media | planned |
| A-B repeat; frame stepping; navigation keys | manual |

## Fedora release criteria and openQA (Fedora, openSUSE, GNOME)

Desktop items of Fedora's Basic, Beta and Final release criteria, and the
desktop tests of the three openQA suites, that the lists above do not cover.
Most critical first. Already covered elsewhere and left out here: login,
logout and lock screen, the first-login wizard, notifications, sound
playback, Xwayland, workspaces, dark mode, screenshots, failed services,
crashes and the journal.

| Criterion or test | Item | Status |
|---|---|---|
| Fedora Beta "shutdown, reboot, login, logout" | Log out with the desktop's own dialog (Confirm) | auto `[power]` |
| Fedora Beta "shutdown, reboot, login, logout" | Restart from the panel's power menu | auto `[power]` (boot 3) |
| Fedora Beta "shutdown, reboot, login, logout" | Shut down with the login screen's power button (at the very end, after installing again) | auto `[power]` |
| Fedora Beta "shutdown, reboot, login, logout" | Shut down from the panel's power menu: the dialog asks; Cancel stops its 60-second countdown | auto `[power]` (the shutdown itself is the login screen's, at the end) |
| Fedora Beta "suspend and resume" | Suspend from the panel's power menu (S3), wake, the lock screen, unlock; same session | auto `[suspend]` (virtio-vga on a PCIe port with x-pcie-pm-no-soft-reset, else the VM's display stays off after waking) |
| Fedora Basic/Final "window manager functionality" | Maximize and restore (Super+M), full screen (Super+F11) | auto `[wm]` |
| Fedora Basic/Final "window manager functionality" | Alt+Tab both ways, tiling (Super+Y) and focus between tiles | auto `[wm]` |
| Fedora Basic/Final "window manager functionality" | Minimize, move and resize with the mouse, close button | auto `[wm]` |
| Fedora Basic "expected boot behavior" / virtual consoles | Ctrl+Alt+F3 to a text console, log in there, and back (session and login screen) | auto `[console]` |
| Fedora Final "default application functionality" | Files open in the default app: text, image, folder (and sound: see known) | auto `[open]` |
| Fedora Final "default application functionality" | Every app starts and closes (System Monitor and Viewer here; the others in the sections above) | auto `[apps]` |
| Screen lock on idle (Fedora, openSUSE, GNOME screen lock tests) | After the screen-off time the screen turns off and the session locks; input wakes it; the password unlocks | auto `[idle]` (15 s) |
| Fedora desktop_notifications; GNOME notifications | The applet lists a notification after its pop-up has gone; Do Not Disturb holds pop-ups back, and they show again when it is off | auto `[notify]` |
| Fedora Final "desktop keyring" | The login password unlocks the keyring; secrets are stored and read back; a locked keyring prompts | auto `[keyring]`; first login known (see below) |
| Fedora Basic "required applications" | A web browser | informational: none installed with the package; COSMIC's defaults name firefox-esr |
| Fedora Final "dual monitor setup" | Second display; arrange; mirror | planned (two virtual outputs) |
| Fedora Beta/Final "desktop panel", "default panel functionality" | Each panel applet opens and closes (clock, keyboard layout, accessibility, tiling, sound, Bluetooth, network, battery, notifications); the calendar turns a month; the volume slider sets the volume | auto `[panel]`; Escape does not close them (known) |
| Fedora Basic "basic networking" (desktop side) | Wired connection in Settings: static address, reconnect | planned |
| openSUSE keyboard_layout_gdm, keymap_or_locale | Another keyboard layout in the session (German: the keys Z and Y swap); the panel shows it | auto `[layout]` |
| openSUSE keyboard_layout_gdm | The layout on the lock screen (a password with a "y" typed in German) | auto `[layout]` |
| openSUSE keyboard_layout_gdm | The layout at the login screen: the system's (/etc/default/keyboard, German here) | auto `[layout]` from build 14 (cosmic-greeter-debian-start); known on older builds (pop-os/cosmic-greeter#519), where the greeter's own xkb_config is checked as the workaround |
| Fedora Final "critical path translations" | German chosen in Settings (Region & language) applies at the next login | known `[language]`: does nothing on Debian (see below) |
| Fedora Final "critical path translations" | With German as the system language the panel and Settings are translated | auto `[language]` |
| Fedora Final "critical path translations"; GNOME welcome locales | Login screen and wizard translated; Arabic (right to left) and Japanese (fonts) | planned |
| Fedora Final "user switching" | A second user chosen in the login screen's list logs in, gets their own first-login wizard and a working desktop; back to the first user | auto `[users]` (boot 3; the user is added with useradd, as Settings' Add user fails) |
| Fedora Final "user switching" | Switching users without logging out | n/a: COSMIC 1.11 has no Switch user (the power menu has Lock and Log out) |
| Fedora Beta/Final "printing" | Print to a PDF printer | auto `[print]` (Print Settings' test page to cups-pdf; no COSMIC app prints in 1.11) |
| Fedora Final "update notification" | The desktop tells about updates | n/a: COSMIC 1.11 has no update notification (the Store's only notification is for an operation still running) |
| GNOME gnome_audio; Fedora Final "working sound" | Recording; the sound heard is the sound played | planned |
| openSUSE toolkits | Qt 5, Qt 6, GTK 3 and GTK 4 programs open windows and close (qt5ct, qt6ct, Print Settings, zenity); X11 by xeyes | auto `[toolkit]` |
| openSUSE glxgears; Fedora graphics validation | OpenGL on Wayland (es2gears_wayland) and X11 (glxgears) and Vulkan (vkcube) draw moving pictures on software rendering | auto `[graphics]` (mesa-utils, vulkan-tools as test tools) |
| openSUSE toolkits | SDL clients | planned |
| openSUSE gnomecase | An entry in ~/.config/autostart runs at login | auto `[autostart]` (set up in boot 2, checked after the reboot) |
| openSUSE gnomecase change_password | Change the password in Settings (Users); the lock screen takes the new one | known `[password]`: the change does nothing (see below) |
| openSUSE gnomecase | Automatic login | auto `[autologin]` (greetd initial_session; COSMIC has no setting) |
| Fedora remote desktop; Fedora/GNOME branding and accessibility | | n/a (no COSMIC RDP server; branding; accessibility is out of scope here) |

## Fedora's desktop validation matrix, and NixOS

No distribution tests COSMIC as thoroughly as its blocking desktops. Fedora
ships COSMIC (spin and Atomic) but neither its openQA (os-autoinst-distri-fedora
tests only GNOME and KDE) nor its desktop validation matrix
(Test_Results:Current_Desktop_Test, columns Workstation, KDE and optional
desktops) has COSMIC, which is not release-blocking. openSUSE's openQA has no
COSMIC tests. NixOS has a small VM test (nixos/tests/cosmic): log in (and an
autologin variant), an autostart entry runs, the session is Wayland, a pkexec
prompt is answered, seven apps open a window.

Fedora's desktop test cases, as this suite covers them for COSMIC:

| Milestone | Fedora test case | Here |
|---|---|---|
| Basic | window manager | auto `[wm]` |
| Basic | desktop_browser | informational: no browser comes with the package |
| Basic | desktop_app_basic: terminal | auto (vm-session terminal, `[launcher-10]`) |
| Beta | desktop_login | auto (vm-session: wrong and right password, log out, log in again) |
| Beta | audio_basic | auto `[player]`, volume keys (output only, no hardware) |
| Beta | desktop_panel_basic | auto `[panel]` |
| Beta | desktop_automount | auto `[files-28]` (USB stick) |
| Beta | workstation_core_applications | auto `[apps]` and the app sections above |
| Beta | desktop_update_graphical | auto `[store]` (a local repository with a newer package) |
| Beta/Final | Printing_New_Printer (real printer) | n/a in a VM |
| Final | Printing_PDF | auto `[print]` (Print Settings' test page; cups-pdf as a test tool) |
| Final | desktop_update_notification | n/a (COSMIC 1.11 has no update notification) |
| Final | desktop_error_checks | auto (journal, crash reports, failed units, each boot) |
| Final | desktop_panel_advanced | auto `[panel-advanced]` (add the on-screen keyboard applet in Settings, use it, remove it) |
| Final | desktop_keyring | auto `[keyring]` |
| Final | desktop_user_switching | auto `[users]` (log out and in as another user; COSMIC has no Switch user) |
| Final | desktop_app_basic: file manager, image viewer, text editor, system settings | auto (Files, Viewer, Edit, Settings sections) |
| Final | desktop_app_basic: package manager | auto `[store]` (search, install, open, uninstall) |
| Final | desktop_app_basic: archive manager | auto `[archive]` (COSMIC Files: Compress a folder to zip; Extract a zip and a tar.gz) |
| Final | desktop_app_basic: document viewer, problem reporter, help viewer | n/a (COSMIC 1.11 has none) |
| Optional | desktop_app_basic_others | auto `[apps]` (System Monitor) |
| Optional | desktop_menus | auto (App Library, launcher) |
| Optional | workstation_theming | auto `[settings-appearance]`, light theme |
| Optional | Printing_New_Printer (virtual printer) | auto `[print]` (Unlock with the admin prompt, Add printer: CUPS-PDF) |
| Optional | bluetooth_headset | n/a in a VM |
| Optional | desktop_graphics_validation | auto `[graphics]` |
| NixOS | autologin variant | auto `[autologin]` |
| NixOS | session is Wayland; autostart; pkexec prompt | auto (vm-session, `[autostart]`) |

## Recurring upstream bugs (regressions.sh)

Checks for the kinds of bugs that keep being reported in COSMIC's issue
trackers (pop-os/cosmic-epoch and the component repositories, the year
before epoch 1.11: about 4,200 issues ranked by reports, reactions and
duplicates). Each check names the issues it guards against.

| Theme | Issues | Here |
|---|---|---|
| Volume changes switch the output, reset the balance or mute | cosmic-settings#1101 (#2034), cosmic-applets#1277, cosmic-osd#188, cosmic-panel#575 | auto `[sound]`: a second output present, balance set in Settings; volume keys and scrolling on the panel icon keep output and balance |
| Sound broken after resume | cosmic-epoch#2580, cosmic-settings-daemon#193 | auto `[suspend]`: same output, volume keys work after waking |
| Workspaces overview crashes | cosmic-epoch#2978, cosmic-workspaces-epoch#264, #340 | auto `[workspaces]`: Super+W and Escape 20 times with a window open; **known**: it crashes several times in 20 (cosmic-workspaces-epoch#340); once cosmic-comp crashed too (llvmpipe) |
| Maximized or tiled state lost after minimize | cosmic-epoch#2743, cosmic-comp#2524, #2132, #1972 | auto `[wm]`: maximized (restored by Alt+Tab and by the dock) and tiled |
| A notification's area keeps blocking clicks; bursts | cosmic-epoch#2726, cosmic-notifications#170 | auto `[notify]` |
| X11 clipboard transfers of 256 KiB and more corrupted | cosmic-comp#2717 | auto `[clipboard]`: 300 KiB both ways, byte for byte |
| Shortcuts fail with a Cyrillic layout | cosmic-epoch#2701, #3264 | auto `[layout]`: us,ru with Russian active: Super+T, Ctrl+A/C in Edit, Ctrl+Shift+V in the terminal |
| Compositor keeps buffers of closed windows | cosmic-comp#2073, #2072 | auto `[leak]`: memfd, file descriptors and memory of cosmic-comp over 20 windows and 10 overviews |
| CPU busy while idle, locked or after unlocking | cosmic-epoch#3733, cosmic-comp#2169 | auto `[cpu]`; **known**: cosmic-comp keeps about half a CPU busy while the screen is locked (cosmic-epoch#3733) |
| Screen cast freezes, portal crashes | xdg-desktop-portal-cosmic#384, #389, #403, #407 | planned (ScreenCast portal client) |
| Disabling an output kills the session | cosmic-comp#2727 | planned (two virtual outputs) |
| Chromium leaves full screen after a second | cosmic-comp#2677, #2685 | planned (needs Chromium in the VM) |
| Typing with fcitx5 | cosmic-comp#2941, cosmic-epoch#3966 | planned |
| Tray icons missing or not opening the app | cosmic-epoch#3217, cosmic-applets#1187 | planned (an AppIndicator test client) |
| Dialogs without keyboard focus | cosmic-edit#494, cosmic-files#1518 | in part (`[files-12]`); planned |

Not testable in this VM: GPU and driver bugs (NVIDIA, hybrid graphics, GPU
resets), real monitors, docks and hubs, Bluetooth and Wi-Fi, games with
pointer capture, touchpad gestures, fingerprint.

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
- Debian's shared-mime-info calls WAV files `audio/vnd.wave`; COSMIC's
  default-apps list and the Player's desktop file only name the old
  `audio/x-wav`, so a WAV file has no default app.
- The login keyring is not unlocked at login without libpam-gnome-keyring
  (gnome-keyring itself is a dependency); now recommended.
- On a user's very first login the login keyring that PAM creates cannot be
  used until the next login: storing a secret waits for a prompt that closes
  at once. It looks like gnome-keyring's own first-login bug, not COSMIC's.
- Typing "system monitor" in the launcher puts Settings' System & Accounts
  page above COSMIC System Monitor.
- Escape does not close a panel applet's popup; clicking its icon again or
  anywhere else does.
- In the VM the network applet showed only Wi-Fi (on, with no Wi-Fi device),
  not the wired connection: the cloud image's network was not managed by
  NetworkManager. The VM now hands it to NetworkManager, as on an installed
  desktop; with systemd-networkd NetworkManager reports no connection and
  PackageKit refuses to refresh ("Cannot refresh cache whilst offline").
- The launcher puts Qt5 Settings above Qt6 Settings for "qt6 settings"
  (digits seem to count for little in its matching).
- A restart from the power menu once hung while stopping the user's
  services, with systemd no longer answering (one run of three; the test now
  saves the blocked tasks and forces the reboot).
- Choosing a language in Settings changes nothing on Debian. Debian's
  systemd refuses SetLocale on purpose (the locales package owns the system
  locale), and the per-user path fails too: Settings hands AccountsService
  "de_DE:de:en_US:en" where one locale is expected. Even a valid AccountsService
  language is not used by the login screen. On Debian the language comes
  from /etc/default/locale (dpkg-reconfigure locales).
- Settings' Add language lists only the locales the system has generated (on
  Debian usually one); there is no way to add another from COSMIC.
- In German the panel's "Workspaces" button stays English, and the clock
  shows a German date with a 12-hour time.
- logind's LockedHint stays "no" while the screen is locked (with Super+Escape
  and on idle), so programs that ask logind cannot tell the session is locked.
- Changing the password and adding a user in Settings (Users) do nothing:
  AccountsService answers "Authentication is required" and no password
  prompt appears; Settings shows no error. The same call made with D-Bus's
  "allow interactive authorization" flag does bring up COSMIC's admin
  prompt, so Settings does not let these calls ask.
- At the default window size Settings' Add user dialog is cut off at the
  bottom: its Administrator switch and its buttons can be reached only with
  the window maximized.
- Print Settings is recommended, but without CUPS it says "Printing service
  not available": printing needs cups, which nothing pulls in.
- The login screen shows the chosen user's keyboard layout (here "de") but
  types with US: since cosmic-greeter 1.5.0 the greeter no longer writes its
  compositor's xkb_config (pop-os/cosmic-greeter#519, open). Choosing the
  layout in the greeter's menu does not help, and neither do
  /etc/default/keyboard or localed. Writing the layout to
  /var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1/xkb_config
  (as cosmic-greeter) does. The lock screen types with the session's layout.
  The package now does this: greetd starts
  /usr/libexec/cosmic-greeter-debian-start, which writes the layout from
  /etc/default/keyboard there (unless an administrator's own file is there)
  and runs cosmic-greeter-start.
- Renaming the device in Settings (About) does nothing on Debian:
  Settings calls hostnamed's SetStaticHostname with "interactive" false,
  and Debian's polkit wants an admin password (auth_admin_keep), so there is
  no prompt and no error and the old name comes back. Same cause as the
  password change. Upstream reports it working on Pop!_OS (#1047).
- The lock screen's keyboard button opens an on-screen keyboard (in the
  session's layout); Escape does not close it, its x button does.
- Once (run 21), on Super+2, the desktop's cosmic-files-applet panicked with
  "Create pixel map" in libcosmic's software renderer and was restarted by
  the session: pop-os/libcosmic#1491 (open, same libcosmic commit), a surface
  drawn before its first configure. Reported as known.
- COSMIC Store lists, installs and updates Debian software only through
  PackageKit, which the package only suggested: without it the Store shows
  no Debian apps. Recommended from build 15.
- The Store shows a generic box for every Debian app: Debian's appstream
  downloads app icons only with apt-config-icons (GNOME Software's Debian
  plugin and KDE Discover depend on it). Recommended from build 15.
- The Store reads the app catalogue only when it starts: after Check for
  updates fetches new AppStream data, new apps show up only after the Store
  is opened again.
- No COSMIC app can print in 1.11 (Edit, Files, Terminal have no Print);
  printing works from Print Settings and from GTK and Qt apps.
- Print Settings asks for the admin password (COSMIC's prompt) to unlock, and
  adding a printer may then ask CUPS's own user and password once more. Only
  members of lpadmin may add printers: the Debian installer puts its first
  user there; other users need "sudo adduser NAME lpadmin".
- Print Settings started from a terminal over SSH cannot unlock (polkit sees
  a remote session); started from the launcher it can.
- COSMIC has no setting for automatic login; greetd's initial_session works.
- Now and then after a login (automatic or with a password) stray pixels
  show in the clear area beside the dock until the next login (VM only so
  far; not confirmed upstream). `[autologin]` compares the desktop before
  and after an automatic login and reports it.
- Extract in COSMIC Files puts an archive's contents in a folder named after
  it, even when the archive holds a single folder of that name
  (docs.zip -> docs/docs/).
- The workspaces overview (Super+W) crashes now and then, several times in
  20 openings in the VM: after a capture protocol error it loses its Wayland
  connection and panics in wgpu ("Surface does not support the adapter's
  queue family"), in the software renderer ("Create softbuffer context") or
  in screencopy.rs; cosmic-session restarts it, and while it restarts
  Super+W does nothing (pop-os/cosmic-workspaces-epoch#340, open).
- Once (CI, build 15) cosmic-comp itself died during those overview crashes:
  "Erroneous EGL call didn't set EGLError", then a SIGSEGV in llvmpipe's
  threads (libgallium, Mesa 25.0.7: the software renderer this VM uses, not
  a GPU driver). cosmic-session started a new compositor and the desktop came
  back, but the open windows were gone. Not confirmed upstream (the libgallium
  crashes reported there are SIGABRT on NVIDIA hybrid laptops,
  cosmic-comp#2746, #2843). `[workspaces]` reports it and starts a new
  session for the checks after it.
- Now and then the lock screen shows without keyboard focus in its password
  field: the password typed goes nowhere until the field is clicked
  (pop-os/cosmic-greeter#286, open; reports say more often after waking and
  with two monitors). In the VM it came in streaks, whether the screen was
  locked with Super+Escape or by logind. Every unlock in the tests clicks the
  field and types again when the lock card is still shown, and reports it.
- While the screen is locked cosmic-comp keeps about half a CPU busy; idle
  and unlocked it uses next to nothing (pop-os/cosmic-epoch#3733, open,
  reports the same on real hardware).
- Balance set outside COSMIC (pactl, pavucontrol) is reset by the volume
  keys; balance set in Settings is kept (cosmic-settings#1101 fixed that
  case).
- With Russian as the only layout (no Latin one) Super+T does nothing;
  with us,ru, as Debian sets it up, all shortcuts work.
- X11 apps can read the clipboard only while one of them has the focus
  (by design in cosmic-comp).
- cosmic-settings-daemon's process name is cut to "cosmic-settings", the
  same as Settings': tools that match the short name confuse the two (the
  test once killed the daemon this way, and had wrongly noted that Settings
  stays running after its window closes).
- Adding or removing a panel applet restarts all the panel's applets. The
  notifications daemon keeps its connection to the old notifications applet
  and from then on logs "Failed to notify applet of notification ... Broken
  pipe" for every notification (pop-os/cosmic-notifications#116, open:
  dead applet connections are never pruned).
- Up to build 15 the package recommended xinit (as upstream's cosmic-greeter
  does), which pulls in the X.Org server (xserver-xorg-core) and with it
  keyboard-configuration, which asks for the keyboard layout when installed
  on a system that lacks it (the VM's cloud image; an installed desktop has
  it). Later builds do not recommend it (the login screen needs startx only
  for X11 sessions); the install check makes sure no X.Org server comes in.
- colord, installed together with cups, can be started by cupsd before its
  own user exists and then fails once (Debian's install order; seen when the
  test installs cups mid-session).

