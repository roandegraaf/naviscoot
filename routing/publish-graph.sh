#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/routing/build/nl"
FILES=(tiles.tar valhalla.json admins.sqlite fused_access.csv)
TAG="${1:-graph-$(date -u +%Y%m%d-%H%M)}"
REPO="${GRAPH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

for f in "${FILES[@]}"; do
  [[ -f "$SRC/$f" ]] || { echo "missing $SRC/$f; run routing/refresh.sh first" >&2; exit 1; }
done
if grep -q "nl-next" "$SRC/valhalla.json"; then
  echo "$SRC/valhalla.json still points at nl-next" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
(cd "$SRC" && shasum -a 256 "${FILES[@]}") > "$STAGE/SHA256SUMS"
cat "$STAGE/SHA256SUMS"

NOTES="Naviscoot graph unit ($(date -u +%Y-%m-%d)): Valhalla 3.9.1 tiles for the Netherlands with fused bromfiets access around Amersfoort.

Contains information from OpenStreetMap, © OpenStreetMap contributors, available under the Open Database License (ODbL): https://www.openstreetmap.org/copyright.
Contains NDW verkeersborden data (CC0)."

gh release create "$TAG" --repo "$REPO" --title "Graph $TAG" --notes "$NOTES" \
  "${FILES[@]/#/$SRC/}" "$STAGE/SHA256SUMS"

echo
echo "published. Set GRAPH_BASE_URL=https://github.com/$REPO/releases/download/$TAG in Coolify and redeploy."
