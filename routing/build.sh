#!/usr/bin/env bash
set -euo pipefail

IMAGE="${VALHALLA_IMAGE:-ghcr.io/valhalla/valhalla:3.9.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-routing/build/nl}"
PBF="${PBF:-data/build/routable.osm.pbf}"
ADMIN_PBF="${ADMIN_PBF:-data/raw/netherlands-latest.osm.pbf}"
GRAPH_LUA="${GRAPH_LUA:-routing/valhalla/graph.lua}"
USE_ADMINS="${USE_ADMINS:-1}"
LOCAL_EXPANSION_M="${LOCAL_EXPANSION_M:-1000000}"

usage() {
  echo "usage: routing/build.sh config|admins|tiles|all" >&2
  echo "env: OUT PBF ADMIN_PBF GRAPH_LUA (path or 'stock') USE_ADMINS (1|0) VALHALLA_IMAGE; paths relative to the repo root" >&2
  exit 2
}

in_container() {
  docker run --rm -v "$ROOT:/repo" -w /repo "$IMAGE" "$@"
}

config() {
  mkdir -p "$ROOT/$OUT"
  local args=(
    --mjolnir-tile-dir "/repo/$OUT/tiles"
    --mjolnir-tile-extract "/repo/$OUT/tiles.tar"
    --mjolnir-admin "/repo/$OUT/admins.sqlite"
    --mjolnir-timezone "/repo/$OUT/timezones.sqlite"
    --mjolnir-concurrency "$(getconf _NPROCESSORS_ONLN)"
    --service-limits-max-exclude-locations 2000
    --service-limits-trace-max-distance 400000
    --service-limits-trace-max-shape 50000
  )
  if [[ "$GRAPH_LUA" != "stock" ]]; then
    args+=(--mjolnir-graph-lua-name "/repo/$GRAPH_LUA")
  fi
  in_container valhalla_build_config "${args[@]}" > "$ROOT/$OUT/valhalla.json"
  python3 - "$ROOT/$OUT/valhalla.json" "$USE_ADMINS" "$LOCAL_EXPANSION_M" <<'PY'
import json, sys
path, use_admins, local_expansion = sys.argv[1], sys.argv[2], float(sys.argv[3])
conf = json.load(open(path))
if use_admins != "1":
    conf["mjolnir"].pop("admin", None)
for algorithm in ("bidirectional_astar", "unidirectional_astar", "costmatrix"):
    limits = conf["thor"][algorithm]["hierarchy_limits"]["expand_within_distance"]
    limits["1"] = max(limits["1"], local_expansion)
    limits["2"] = local_expansion
json.dump(conf, open(path, "w"), indent=2)
PY
  echo "wrote $OUT/valhalla.json"
}

admins() {
  in_container valhalla_build_admins -c "/repo/$OUT/valhalla.json" "/repo/$ADMIN_PBF"
}

tiles() {
  rm -rf "$ROOT/$OUT/tiles" "$ROOT/$OUT/tiles.tar"
  in_container valhalla_build_tiles -c "/repo/$OUT/valhalla.json" "/repo/$PBF"
  in_container valhalla_build_extract -c "/repo/$OUT/valhalla.json" -v --overwrite
  find "$ROOT/$OUT" -maxdepth 1 -name '*.bin' -delete
}

case "${1:-}" in
  config) config ;;
  admins) admins ;;
  tiles) tiles ;;
  all)
    config
    if [[ "$USE_ADMINS" == "1" ]]; then admins; fi
    tiles
    ;;
  *) usage ;;
esac
