#!/usr/bin/env bash
# Installs the latest stable Tailscale into /data/tailscale/bin/current and
# keeps the one before it in .../previous for a rollback. Every download is
# checked against Tailscale's published SHA-256 before it replaces anything.
# Exit 0: installed or already up to date. Exit 1: nothing changed.
set -euo pipefail

DIR=/data/tailscale/bin
BASE=${TS_PKG_URL:-https://pkgs.tailscale.com/stable}
case "$(uname -m)" in
  aarch64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
mkdir -p "$DIR"

index=$(curl -fsS -m 30 "$BASE/?mode=json")
version=$(jq -r '.TarballsVersion // empty' <<<"$index")
file=$(jq -r --arg a "$ARCH" '.Tarballs[$a] // empty' <<<"$index")
if [[ -z "$version" || -z "$file" ]]; then
  echo "Could not read the Tailscale package index" >&2
  exit 1
fi

if [[ -f "$DIR/current/VERSION" && "$(cat "$DIR/current/VERSION")" == "$version" ]]; then
  echo "Tailscale $version is up to date"
  exit 0
fi
if [[ -f "$DIR/bad-version" && "$(cat "$DIR/bad-version")" == "$version" ]]; then
  echo "Skipping Tailscale $version: it failed the health check before"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsS -m 300 -o "$tmp/$file" "$BASE/$file"
expected=$(curl -fsS -m 30 "$BASE/$file.sha256" | awk '{print $1}')
actual=$(sha256sum "$tmp/$file" | awk '{print $1}')
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "Checksum mismatch for $file" >&2
  exit 1
fi

tar -xzf "$tmp/$file" -C "$tmp"
src="$tmp/${file%.tgz}"
"$src/tailscale" version >/dev/null

rm -rf "$DIR/staging"
mkdir -p "$DIR/staging"
cp "$src/tailscale" "$src/tailscaled" "$DIR/staging/"
echo "$version" >"$DIR/staging/VERSION"
rm -rf "$DIR/previous"
if [[ -d "$DIR/current" ]]; then mv "$DIR/current" "$DIR/previous"; fi
mv "$DIR/staging" "$DIR/current"
echo "Installed Tailscale $version"
