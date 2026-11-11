#!/bin/bash
# Write DEBIAN/postinst (and postrm) for a staged package root, as
# dh_installsysusers, dh_installtmpfiles and dh_installsystemd would: create the
# system users from usr/lib/sysusers.d and the directories from
# usr/lib/tmpfiles.d when the package is configured, and reload systemd for the
# shipped system units (which are not enabled).
# Without it cosmic-greeter's user does not exist: systemd-sysusers.service
# only runs at boot after /usr changes, so a reboot does not create it either
# (found by the VM session test of build 10).
#
# Usage: make-maintscripts.sh <staged-root>
# Prints the extra Depends (", a, b" or nothing) for the control file.
set -euo pipefail

ROOT=$1
cd "$ROOT"

mapfile -t sysusers < <(find usr/lib/sysusers.d -maxdepth 1 -name '*.conf' -printf '%f\n' 2>/dev/null | sort)
mapfile -t tmpfiles < <(find usr/lib/tmpfiles.d -maxdepth 1 -name '*.conf' -printf '%f\n' 2>/dev/null | sort)
mapfile -t units < <(find usr/lib/systemd/system -maxdepth 1 -name '*.service' -printf '%f\n' 2>/dev/null | sort)
[ "${#sysusers[@]}" -gt 0 ] || [ "${#tmpfiles[@]}" -gt 0 ] || [ "${#units[@]}" -gt 0 ] || exit 0

mkdir -p DEBIAN
{
    echo '#!/bin/sh'
    echo 'set -e'
    echo 'case "$1" in'
    echo '    configure|abort-upgrade|abort-deconfigure|abort-remove)'
    if [ "${#sysusers[@]}" -gt 0 ]; then
        echo "        systemd-sysusers \${DPKG_ROOT:+--root=\"\$DPKG_ROOT\"} ${sysusers[*]}"
    fi
    if [ "${#tmpfiles[@]}" -gt 0 ]; then
        echo '        if [ -z "${DPKG_ROOT:-}" ] && [ -d /run/systemd/system ]; then'
        echo "            systemd-tmpfiles --create ${tmpfiles[*]} > /dev/null || true"
        echo '        fi'
    fi
    if [ "${#units[@]}" -gt 0 ]; then
        # System units are shipped but not enabled; make them known to systemd.
        echo '        if [ -z "${DPKG_ROOT:-}" ] && [ -d /run/systemd/system ]; then'
        echo '            systemctl --system daemon-reload > /dev/null || true'
        echo '        fi'
    fi
    echo '        ;;'
    echo 'esac'
    echo 'exit 0'
} > DEBIAN/postinst
chmod 0755 DEBIAN/postinst

if [ "${#units[@]}" -gt 0 ]; then
    cat > DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] && [ -d /run/systemd/system ]; then
    systemctl --system daemon-reload > /dev/null || true
fi
exit 0
EOF
    chmod 0755 DEBIAN/postrm
fi

deps=""
[ "${#sysusers[@]}" -gt 0 ] && deps="$deps, systemd | systemd-standalone-sysusers | systemd-sysusers"
[ "${#tmpfiles[@]}" -gt 0 ] && deps="$deps, systemd | systemd-standalone-tmpfiles"
echo "$deps"
