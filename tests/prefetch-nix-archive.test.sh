#!/usr/bin/env bash
#
# Tests for scripts/prefetch-nix-archive.sh.
#
# Run it directly: tests/prefetch-nix-archive.test.sh
# It needs bash, curl, zstd and python3. It never reaches the network.

set -uo pipefail

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
root="${here%/*}"
script="$root/scripts/prefetch-nix-archive.sh"
server="$here/fake-release-server.py"

version="9.9.9"
release="v99"

pass=0
fail=0
workdir="$(mktemp -d)"
servers=()

cleanup() {
  for pid in "${servers[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  rm -rf "$workdir"
}
trap cleanup EXIT

ok() {
  pass=$((pass + 1))
  echo "ok - $1"
}

no() {
  fail=$((fail + 1))
  echo "NOT OK - $1"
  [ $# -lt 2 ] || printf '    %s\n' "$2"
}

check() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    no "$1" "expected: $3" "got:      $2"
  fi
}

assert() {
  local name="$1"
  shift
  if "$@"; then ok "$name"; else no "$name"; fi
}

refute() {
  local name="$1"
  shift
  if "$@"; then no "$name"; else ok "$name"; fi
}

intact() {
  zstd -q -t "$1" 2> /dev/null
}

contains() {
  if [[ "$2" == *"$3"* ]]; then
    ok "$1"
  else
    no "$1" "expected to contain: $3" "got: $2"
  fi
}

# The archive name the script must produce is the one nix-quick-install-action
# builds from nix_archives_url, so the fixture is named the same way.
system() {
  local arch
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *) echo "unsupported test host: $(uname -m)" >&2 && exit 1 ;;
  esac
  case "$OSTYPE" in
    darwin*) echo "$arch-darwin" ;;
    *) echo "$arch-linux" ;;
  esac
}

archive_name="nix-$version-$(system).tar.zstd"

make_archive() {
  local dir="$workdir/fixture"
  mkdir -p "$dir/payload"
  # Big enough that half of it is a genuinely broken zstd frame.
  head -c 400000 /dev/urandom > "$dir/payload/blob"
  tar -c -C "$dir/payload" . | zstd -q -o "$dir/$archive_name"
  echo "$dir/$archive_name"
}

start_server() {
  local mode="$1" archive="$2" count="$3"
  local portfile="$workdir/port.$RANDOM"
  : > "$count"
  # The server must not inherit this function's stdout: a command substitution
  # around start_server would then wait for the server to exit.
  python3 "$server" "$mode" "$archive" "$count" "$portfile" > "$workdir/server.log" 2>&1 &
  servers+=("$!")
  for _ in $(seq 1 100); do
    [ -s "$portfile" ] && break
    sleep 0.05
  done
  [ -s "$portfile" ] || {
    echo "the fake release server did not start" >&2
    exit 1
  }
  echo "http://127.0.0.1:$(cat "$portfile")"
}

run_prefetch() {
  local dest="$1" base="$2"
  shift 2
  env NIX_VERSION="$version" \
    NIX_QUICK_INSTALL_RELEASE="$release" \
    DEST_DIR="$dest" \
    ARCHIVES_BASE_URL="$base" \
    RETRY_DELAY=0 \
    "$@" \
    "$script" 2>&1
}

fixture="$(make_archive)"

# A healthy download lands under the exact name nix-quick-install-action asks
# for, and the file survives an integrity check.
dest="$workdir/dest-good"
out="$(run_prefetch "$dest" "file://${fixture%/*}")"
status=$?
check "a healthy download exits zero" "$status" "0"
if [ -f "$dest/$archive_name" ]; then
  ok "a healthy download writes DEST_DIR/$archive_name"
else
  no "a healthy download writes DEST_DIR/$archive_name" "$out"
fi
assert "the stored archive passes an integrity check" intact "$dest/$archive_name"

# The failure this whole script exists for: a body that arrives complete as far
# as the transfer is concerned, but decompresses to nothing. Only the integrity
# check can see it, and it must drive a retry rather than a job failure.
dest="$workdir/dest-silent"
count="$workdir/count-silent"
base="$(start_server silent-first "$fixture" "$count")"
out="$(run_prefetch "$dest" "$base")"
status=$?
check "a silently truncated body is retried, not accepted" "$status" "0"
check "the retry re-downloads once" "$(wc -l < "$count")" "2"
if intact "$dest/$archive_name"; then
  ok "the retry stores the whole archive"
else
  no "the retry stores the whole archive" "$out"
fi

# When every attempt truncates, the step has to fail — but it must say the
# download failed, not leave a tar or zstd message standing in for the cause.
dest="$workdir/dest-closed"
count="$workdir/count-closed"
base="$(start_server closed-always "$fixture" "$count")"
out="$(run_prefetch "$dest" "$base" ATTEMPTS=3)"
status=$?
refute "an always-truncated download fails" [ "$status" -eq 0 ]
check "every attempt is spent" "$(wc -l < "$count")" "3"
contains "the message names the download" "$out" "$base/$archive_name"
contains "the message names the attempt count" "$out" "3 attempts"
refute "a failed download leaves no archive behind" [ -e "$dest/$archive_name" ]

# A 404 is a wrong version or a wrong release tag. Retrying it only delays the
# report, so the script must stop at the first one.
dest="$workdir/dest-404"
count="$workdir/count-404"
base="$(start_server missing "$fixture" "$count")"
out="$(run_prefetch "$dest" "$base" ATTEMPTS=3)"
status=$?
refute "a missing archive fails" [ "$status" -eq 0 ]
check "a missing archive is not retried" "$(wc -l < "$count")" "1"
contains "the message names the download" "$out" "$base/$archive_name"

# Every other HTTP error is the transient class the retry exists for: GitHub
# serves 5xx under load, and a release asset redirect can expire into a 403.
# Only 404 may skip the retry.
dest="$workdir/dest-5xx"
count="$workdir/count-5xx"
base="$(start_server server-error "$fixture" "$count")"
out="$(run_prefetch "$dest" "$base" ATTEMPTS=3)"
status=$?
refute "a server error fails after every attempt" [ "$status" -eq 0 ]
check "a server error is retried" "$(wc -l < "$count")" "3"
contains "the message names the attempt count" "$out" "3 attempts"

# The install step reads the archive from the path the script chose, so the
# script reports that path rather than the two steps repeating a literal.
dest="$workdir/dest-output"
outputs="$workdir/github-output"
: > "$outputs"
run_prefetch "$dest" "file://${fixture%/*}" GITHUB_OUTPUT="$outputs" > /dev/null
check "the script reports the archive directory" "$(cat "$outputs")" "dir=$dest"

# The prefetch URL is built from a release tag this repository hardcodes, while
# the download itself is done by a pinned action. If the two drift, the prefetch
# warms the wrong archive and the pinned action downloads unprotected. Every
# action that installs Nix has to carry both halves.
for manifest in action.yml update-flake/action.yml; do
  pin="$(sed -n 's|.*uses: nixbuild/nix-quick-install-action@\([^ ]*\).*|\1|p' "$root/$manifest" | sort -u)"
  env_release="$(sed -n 's|.*NIX_QUICK_INSTALL_RELEASE: *\([^ ]*\).*|\1|p' "$root/$manifest" | sort -u)"
  assert "$manifest pins nix-quick-install-action" [ -n "$pin" ]
  check "$manifest pre-fetches the release it pins" "$env_release" "$pin"

  # An action reaches the script through its own directory, so a sub-action has
  # to climb out of it. Only a real run would otherwise report a wrong path.
  action_path="$root/$(dirname "$manifest")"
  # shellcheck disable=SC2016 # the manifest holds the literal $GITHUB_ACTION_PATH
  ref="$(sed -n 's|.*run: "\(\$GITHUB_ACTION_PATH[^"]*prefetch-nix-archive.sh\)".*|\1|p' "$root/$manifest")"
  assert "$manifest runs the pre-fetch through \$GITHUB_ACTION_PATH" [ -n "$ref" ]
  assert "the path $manifest uses resolves to the script" \
    [ -x "${ref/\$GITHUB_ACTION_PATH/$action_path}" ]
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
