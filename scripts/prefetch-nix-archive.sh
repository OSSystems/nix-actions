#!/usr/bin/env bash
#
# Download the Nix archive that nix-quick-install-action would fetch, with a
# bounded retry and an integrity check, and store it under DEST_DIR so that
# action can be pointed at the verified copy through nix_archives_url.
#
# GitHub sometimes serves a truncated release asset. nix-quick-install-action
# pipes the download straight into tar, so a short body cannot be retried and
# surfaces as "unexpected end of file" from zstd — a message that names the
# extraction and fails the job before any project tool runs. Downloading to a
# file first makes the body checkable, retryable, and reportable as a download.
#
# Inputs (environment):
#   NIX_VERSION                 Nix version to fetch, e.g. 2.29.2
#   NIX_QUICK_INSTALL_RELEASE   Release tag holding the archives, e.g. v34
#   DEST_DIR                    Directory to store the archive in
#   ARCHIVES_BASE_URL           Directory URL to fetch from (default: the
#                               nix-quick-install-action release)
#   ATTEMPTS                    Download attempts (default: 3)
#   RETRY_DELAY                 Seconds before the second attempt; the wait
#                               grows with each attempt (default: 5)

set -euo pipefail

: "${NIX_VERSION:?NIX_VERSION must be set}"
: "${NIX_QUICK_INSTALL_RELEASE:?NIX_QUICK_INSTALL_RELEASE must be set}"
: "${DEST_DIR:?DEST_DIR must be set}"

attempts="${ATTEMPTS:-3}"
retry_delay="${RETRY_DELAY:-5}"
base_url="${ARCHIVES_BASE_URL:-https://github.com/nixbuild/nix-quick-install-action/releases/download/$NIX_QUICK_INSTALL_RELEASE}"

case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  arm64 | aarch64) arch=aarch64 ;;
  *)
    echo "::error::Cannot pre-fetch the Nix archive: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac

case "$OSTYPE" in
  darwin*) sys="$arch-darwin" ;;
  linux*) sys="$arch-linux" ;;
  *)
    echo "::error::Cannot pre-fetch the Nix archive: unsupported OS type $OSTYPE" >&2
    exit 1
    ;;
esac

# nix-quick-install-action appends this same name to nix_archives_url, so the
# stored file has to carry it exactly.
name="nix-$NIX_VERSION-$sys.tar.zstd"
url="$base_url/$name"

if command -v zstd > /dev/null 2>&1; then
  test_archive=(zstd -q -t)
elif command -v unzstd > /dev/null 2>&1; then
  test_archive=(unzstd -q -t)
else
  echo "::error::Cannot check the Nix archive: neither zstd nor unzstd is installed" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp "$DEST_DIR/.nix-archive.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

attempt=1
while true; do
  echo "Fetching the Nix archive from $url (attempt $attempt of $attempts)"

  status=0
  # --speed-limit/--speed-time bound a stalled body: without them a connection
  # that opens and then delivers nothing holds the attempt until the job's own
  # timeout, and the retry is no longer bounded in wall time. A file:// URL
  # reports no HTTP status, so 000 stands for "not an HTTP transfer".
  http="$(
    curl -sSL -L --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
      -w '%{http_code}' -o "$tmp" "$url"
  )" || status=$?

  # A 404 is a wrong Nix version or a wrong release tag, never a bad transfer,
  # so retrying it only delays the report. Every other HTTP error — a 5xx under
  # load, an expired asset redirect — is the transient class this retry exists
  # for, and must be retried.
  if [ "$http" = "404" ]; then
    echo "::error::The Nix archive does not exist: $url. Check nix-version against the nix-quick-install-action release." >&2
    exit 1
  fi

  if [ "$status" -eq 0 ] && { [ "$http" = "000" ] || [ "$http" = "200" ]; } &&
    "${test_archive[@]}" "$tmp"; then
    mv "$tmp" "$DEST_DIR/$name"
    trap - EXIT
    echo "Stored the verified Nix archive at $DEST_DIR/$name"
    # The install step reads the archive from here, so it learns the path from
    # this script rather than repeating it.
    [ -z "${GITHUB_OUTPUT:-}" ] || echo "dir=$DEST_DIR" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  echo "The Nix archive arrived incomplete or corrupt (curl exit $status, HTTP $http)" >&2

  if [ "$attempt" -ge "$attempts" ]; then
    echo "::error::Failed to download the Nix archive after $attempts attempts: $url" >&2
    exit 1
  fi

  delay=$((retry_delay * attempt))
  echo "Retrying in ${delay}s" >&2
  sleep "$delay"
  attempt=$((attempt + 1))
done
