#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${DEPLOY_HOST:?set DEPLOY_HOST, for example root@your-server}"
DIR="${DEPLOY_DIR:-/data/naviscoot}"
SRC="$ROOT/routing/build/nl"
FILES=(tiles.tar valhalla.json admins.sqlite fused_access.csv)

for f in "${FILES[@]}"; do
  [[ -f "$SRC/$f" ]] || { echo "missing $SRC/$f; run routing/refresh.sh first" >&2; exit 1; }
done
if grep -q "nl-next" "$SRC/valhalla.json"; then
  echo "$SRC/valhalla.json still points at nl-next" >&2
  exit 1
fi

ssh "$HOST" "mkdir -p '$DIR/nl-next'"
rsync -av --partial --progress "${FILES[@]/#/$SRC/}" "$HOST:$DIR/nl-next/"
ssh "$HOST" "set -eu; cd '$DIR'; rm -rf -- nl-prev; if [ -d nl ]; then mv nl nl-prev; fi; mv nl-next nl; ls -la nl"

echo "graph unit uploaded to $HOST:$DIR/nl (previous one in nl-prev)."
echo "restart the naviscoot stack in Coolify: Valhalla and the API read the graph only at start."
