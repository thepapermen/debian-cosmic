#!/bin/bash
# Check every Cargo.lock the COSMIC build uses against the RustSec advisory
# database. Runs as root in a throwaway debian:trixie container.
#
# Fails on any vulnerability advisory that is not in known-advisories.txt, or if
# the pinned inputs no longer match upstream. Everything found is reported,
# including listed advisories and unmaintained, unsound and yanked crates.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=pins.env
. "$HERE/pins.env"
WORK=${WORK:-/work}
SUMMARY=${GITHUB_STEP_SUMMARY:-$WORK/summary.md}
export DEBIAN_FRONTEND=noninteractive CARGO_HOME=$WORK/cargo CARGO_TERM_COLOR=never
mkdir -p "$WORK/json"

# 1. Tools. Rust comes from trixie-backports, pinned by name exactly as in the
# build. cargo-audit is not packaged for trixie, so it is built from crates.io
# at a fixed version; --locked holds it to its own Cargo.lock.
echo 'deb http://deb.debian.org/debian trixie-backports main' \
    > /etc/apt/sources.list.d/trixie-backports.list
printf '%s\n' 'Package: rustc cargo libstd-rust-dev libstd-rust-*' \
    'Pin: release n=trixie-backports' 'Pin-Priority: 990' \
    > /etc/apt/preferences.d/rust-from-backports
apt-get update -q
apt-get install -y -q --no-install-recommends \
    ca-certificates git curl jq rustc cargo gcc libc6-dev pkg-config >/dev/null
dpkg-query -W -f='${Version}\n' cargo | grep -q '~bpo13+'
cargo install -q cargo-audit --version "$CARGO_AUDIT_VERSION" --locked --root "$WORK/tools"
AUDIT=$WORK/tools/bin/cargo-audit
"$AUDIT" audit --version

# 2. COSMIC source at the pinned commit, and a check that upstream's tag still
# points there. A moved tag is a failure, not something to follow.
git init -q "$WORK/epoch"
cd "$WORK/epoch"
git remote add origin "$EPOCH_REPO"
git fetch -q --depth 1 origin "$EPOCH_COMMIT"
git checkout -q FETCH_HEAD
test "$(git rev-parse HEAD)" = "$EPOCH_COMMIT"
tag=$(git ls-remote origin "refs/tags/$EPOCH_TAG" "refs/tags/$EPOCH_TAG^{}" |
    awk '{print $1}' | tail -n 1)
if [ "$tag" != "$EPOCH_COMMIT" ]; then
    echo "Tag $EPOCH_TAG points to ${tag:-nothing}, expected $EPOCH_COMMIT" >&2
    exit 1
fi
git submodule update -q --init --recursive --depth 1

# 3. just's own lockfile, from the crate file crates.io serves, after checking
# it against the checksum in the crates.io index.
sum=$(curl -fsS https://index.crates.io/ju/st/just |
    jq -r --arg v "$JUST_VERSION" 'select(.vers == $v) | .cksum')
curl -fsS -o "$WORK/just.crate" "https://static.crates.io/crates/just/just-$JUST_VERSION.crate"
echo "$sum  $WORK/just.crate" | sha256sum -c --quiet
mkdir -p "$WORK/just"
tar -xzf "$WORK/just.crate" -C "$WORK/just" --strip-components 1 "just-$JUST_VERSION/Cargo.lock"

# 4. Audit. These are the lockfiles at each component's root, which the build
# uses. Patch 0002 adds a libc requirement to cosmic-notifications at build time,
# which this does not see.
locks=()
while IFS= read -r p; do
    [ -f "$p/Cargo.lock" ] && locks+=("$p/Cargo.lock")
done < <(git submodule --quiet foreach 'echo $sm_path')
locks+=("$WORK/just/Cargo.lock")

rc_total=0
fetch=()   # the first run fetches the advisory database, the rest reuse it
for lock in "${locks[@]}"; do
    name=${lock%/Cargo.lock}; name=${name##*/}
    set +e
    "$AUDIT" audit --db "$WORK/db" "${fetch[@]}" --json --file "$lock" > "$WORK/json/$name.json"
    rc=$?
    set -e
    # Exit 1 means vulnerabilities were found; anything else non-zero is a tool error.
    if [ "$rc" -gt 1 ] || ! jq -e . "$WORK/json/$name.json" >/dev/null; then
        echo "cargo audit failed on $lock (exit $rc)" >&2
        exit 2
    fi
    [ "$rc" -eq 1 ] && rc_total=1
    fetch=(--no-fetch)
done

# 5. Report: one row per lockfile, then each advisory once.
jq -rn --arg tag "$EPOCH_TAG" --arg commit "$EPOCH_COMMIT" '
  def kinds: (.warnings // {}) | to_entries | map(.key as $k | .value[] | . + {kind: $k});
  def lockname: input_filename | sub(".*/"; "") | sub("\\.json$"; "");
  [inputs | {lock: lockname, deps: .lockfile["dependency-count"],
     vulns: [.vulnerabilities.list[] | . + {kind: "vulnerability"}], warns: kinds}] as $r
  | "## cargo audit: \($tag) (`\($commit[0:12])`)\n",
    "| Lockfile | Crates | Vulnerabilities | Warnings |", "|---|---|---|---|",
    ($r[] | "| \(.lock) | \(.deps) | \(.vulns | length) | \(.warns | length) |"),
    "\n### Advisories\n",
    "| Kind | ID | Crate | Lockfiles | Title |", "|---|---|---|---|---|",
    ([$r[] | .lock as $l | (.vulns + .warns)[]
        | {kind, id: (.advisory.id // "-"), crate: "\(.package.name) \(.package.version)",
           title: (.advisory.title // "yanked from crates.io"), lock: $l}]
      | group_by([.kind, .id, .crate])
      | sort_by(if .[0].kind == "vulnerability" then 0 else 1 end)[]
      | "| \(.[0].kind) | \(.[0].id) | \(.[0].crate) | \(map(.lock) | unique | join(", ")) | \(.[0].title) |")
' "$WORK"/json/*.json | tee -a "$SUMMARY"

found=$(jq -r '.vulnerabilities.list[].advisory.id' "$WORK"/json/*.json | sort -u)
known=$(grep -oE '^RUSTSEC-[0-9]{4}-[0-9]{4}' "$HERE/known-advisories.txt" | sort -u)
new=$(comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$known") | grep . || true)
{
    echo
    echo "### Not in known-advisories.txt"
    echo
    if [ -n "$new" ]; then printf -- '- %s\n' $new; else echo "None."; fi
} | tee -a "$SUMMARY"

if [ -n "$new" ]; then
    echo "New vulnerability advisories found; see above." >&2
    exit 1
fi
if [ "$rc_total" -ne 0 ]; then
    echo "Only advisories already listed in known-advisories.txt were found."
else
    echo "No vulnerability advisories in ${#locks[@]} lockfiles."
fi
