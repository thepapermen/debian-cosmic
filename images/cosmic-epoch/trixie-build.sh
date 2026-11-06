#!/bin/bash
# TEMPORARY full-stack compile test for Debian 13 "trixie".
#
# Runs each line of the release's own `build` recipe separately, so one failing
# component does not hide the others: a full attempt takes hours. It then runs
# `just install` if everything built, and records what it found.
#
# Exits non-zero unless every component built and installed, and every binary
# resolves its libraries on this system.
set -u

SRC=${SRC:-/build}
DEST=${DEST:-/export}
EVIDENCE=${EVIDENCE:-/compile-evidence.txt}
# Leave room inside GitHub's 6-hour job limit to report what happened.
BUDGET=${BUDGET:-18900}

cd "$SRC" || exit 2

mapfile -t steps < <(
    sed -n '/^build:/,/^install/p' justfile |
        sed -e '1d' -e '$d' -e 's/^[[:space:]]*//' |
        grep -v -e '^mkdir' -e '^$' |
        sed -e 's/{{ just }}/just/g' -e 's/{{ make }}/make/g'
)
if [ "${#steps[@]}" -lt 20 ]; then
    echo "Parsed only ${#steps[@]} build steps from the justfile" >&2
    exit 2
fi

mkdir -p build
passed=()
failed=()
skipped=()
timing=()

for step in "${steps[@]}"; do
    left=$((BUDGET - SECONDS))
    if [ "$left" -le 60 ]; then
        skipped+=("$step")
        continue
    fi
    echo "=== BUILD START: $step ($(date -u +%T), ${left}s left)"
    start=$SECONDS
    timeout "$left" bash -c "$step"
    status=$?
    took=$((SECONDS - start))
    timing+=("$(printf '%6ss  exit=%-3s %s' "$took" "$status" "$step")")
    echo "=== BUILD END: $step exit=$status ${took}s"
    if [ "$status" -eq 0 ]; then
        passed+=("$step")
    else
        failed+=("$step")
    fi
    df -h / | tail -n 1
done

installed=no
if [ "${#failed[@]}" -eq 0 ] && [ "${#skipped[@]}" -eq 0 ]; then
    left=$((BUDGET - SECONDS))
    if [ "$left" -gt 60 ]; then
        mkdir -p "$DEST/usr"
        if timeout "$left" just install "$DEST" /usr; then
            installed=yes
        fi
    fi
fi

elfs=()
if [ "$installed" = yes ]; then
    while IFS= read -r -d '' f; do
        if head -c 4 "$f" | grep -q ELF; then
            elfs+=("$f")
        fi
    done < <(find "$DEST/usr" -type f -print0)
fi

unresolved=no
{
    echo "NOT A RELEASE. Full-stack compile evidence from a temporary test branch."
    echo "== debian_version"
    cat /etc/debian_version
    echo "== cosmic-epoch commit"
    git -C "$SRC" rev-parse HEAD
    echo "== rustc -vV"
    rustc -vV
    echo "== cargo -vV"
    cargo -vV
    echo "== packages from trixie-backports"
    dpkg-query -W -f='${Package} ${Version}\n' | grep -F '~bpo'
    echo "== result"
    echo "steps=${#steps[@]} passed=${#passed[@]} failed=${#failed[@]} skipped=${#skipped[@]} installed=$installed seconds=$SECONDS"
    echo "== failed"
    printf '%s\n' "${failed[@]:-none}"
    echo "== skipped (out of time)"
    printf '%s\n' "${skipped[@]:-none}"
    echo "== timing"
    printf '%s\n' "${timing[@]:-none}"
    echo "== installed ELF files: ${#elfs[@]}"
    for f in "${elfs[@]:-}"; do
        [ -n "$f" ] && ls -l "$f"
    done
    if [ "${#elfs[@]}" -gt 0 ]; then
        echo "== NEEDED sonames, all binaries"
        for f in "${elfs[@]}"; do
            readelf -d "$f" 2>/dev/null | grep NEEDED | grep -o '\[[^]]*\]'
        done | tr -d '[]' | sort -u
        echo "== newest GLIBC symbol version required"
        for f in "${elfs[@]}"; do
            objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9.]*'
        done | sort -uV | tail -n 1
        echo "== unresolved libraries"
        for f in "${elfs[@]}"; do
            ldd "$f" 2>/dev/null | grep -F 'not found' | sed "s|^|$f: |"
        done
    fi
    echo "== end of evidence"
} | tee "$EVIDENCE"

sed -n '/^== unresolved libraries/,/^== end of evidence/p' "$EVIDENCE" | grep -qF 'not found' && unresolved=yes

if [ "${#failed[@]}" -ne 0 ] || [ "${#skipped[@]}" -ne 0 ] || [ "$installed" != yes ] || [ "$unresolved" = yes ]; then
    echo "FULL BUILD DID NOT PASS: failed=${#failed[@]} skipped=${#skipped[@]} installed=$installed unresolved=$unresolved" >&2
    exit 1
fi
echo "FULL BUILD PASSED: all ${#steps[@]} steps built and installed."
