#!/bin/sh
set -eu

BASE="${GRAPH_BASE_URL:?set GRAPH_BASE_URL to the release download URL}"
BASE="${BASE%/}"
ROOT=/repo/routing/build
LIVE="$ROOT/nl"
NEXT="$ROOT/nl-next"
MIN_MEM_MB="${MIN_MEM_AVAILABLE_MB:-2048}"
MIN_DISK_MB="${MIN_DISK_FREE_MB:-2560}"
SUMS=/tmp/SHA256SUMS

fail() { echo "graph: $*" >&2; exit 1; }

mem_total=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)
disk_free=$(df -Pm "$ROOT" | awk 'NR == 2 {print $4}')
echo "graph: host memory ${mem_avail} MB available of ${mem_total} MB; ${disk_free} MB free on the graph volume"

curl -fsSL --retry 3 "$BASE/SHA256SUMS" -o "$SUMS" || fail "cannot fetch $BASE/SHA256SUMS"
[ -s "$SUMS" ] || fail "empty SHA256SUMS at $BASE"

if [ -d "$LIVE" ] && (cd "$LIVE" && sha256sum -c "$SUMS" >/dev/null 2>&1); then
  echo "graph: unit in $LIVE matches $BASE, nothing to download"
  exit 0
fi

# Memory is only gated before a download: on a restart the old Valhalla may still hold its memory.
[ "$mem_avail" -ge "$MIN_MEM_MB" ] || fail "only ${mem_avail} MB memory available, need ${MIN_MEM_MB} MB; not downloading"
[ "$disk_free" -ge "$MIN_DISK_MB" ] || fail "only ${disk_free} MB disk free, need ${MIN_DISK_MB} MB; not downloading"

rm -rf "$NEXT"
mkdir -p "$NEXT"
for f in $(awk '{print $2}' "$SUMS"); do
  case "$f" in */* | .*) fail "unexpected file name in SHA256SUMS: $f" ;; esac
  echo "graph: downloading $f"
  curl -fsSL --retry 3 "$BASE/$f" -o "$NEXT/$f" || fail "download of $f failed"
done
cp "$SUMS" "$NEXT/SHA256SUMS"
(cd "$NEXT" && sha256sum -c SHA256SUMS) || fail "checksum mismatch, keeping the current unit"

rm -rf "$ROOT/nl-prev"
if [ -d "$LIVE" ]; then mv "$LIVE" "$ROOT/nl-prev"; fi
mv "$NEXT" "$LIVE"
rm -rf "$ROOT/nl-prev"
echo "graph: unit from $BASE is live"
