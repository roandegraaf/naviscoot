#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE="routing/build/nl"
STAGE="routing/build/nl-next"
PREV="routing/build/nl-prev"
LIVE_NAME="naviscoot-valhalla"
LIVE_PORT=8002
STAGE_NAME="naviscoot-valhalla-next"
STAGE_PORT="${STAGE_PORT:-8003}"
API_PORT="${API_PORT:-8080}"
BUILD_CONCURRENCY="${CONCURRENCY:-$(( $(getconf _NPROCESSORS_ONLN) / 2 ))}"
LOG="routing/build/refresh.log"

usage() {
  echo "usage: routing/refresh.sh [--force]   fetch, audit, rewrite, build, gate and promote a new graph" >&2
  echo "       routing/refresh.sh rollback    swap $LIVE and $PREV back and restart Valhalla" >&2
  echo "env: REGRESSION_CASES (cases file for the gate), GRAPH_LUA, CONCURRENCY (default half the cores), STAGE_PORT, API_PORT" >&2
  exit 2
}

cd "$ROOT"
if [[ -n "${REGRESSION_CASES:-}" ]]; then
  REGRESSION_CASES="$(cd "$OLDPWD" && realpath "$REGRESSION_CASES")"
  export REGRESSION_CASES
fi

step="setup"
promoted=0
timings=()

say() { echo "==> $*"; }

run_step() {
  step="$1"
  shift
  local started=$SECONDS
  say "$step"
  "$@"
  timings+=("$step $((SECONDS - started))s")
}

log_line() {
  mkdir -p "$(dirname "$LOG")"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$LOG"
}

stop_staging() {
  docker rm -f "$STAGE_NAME" >/dev/null 2>&1 || true
}

relocate_config() {
  python3 - "$1/valhalla.json" "/repo/$2/" "/repo/$1/" <<'PY'
import json, sys
path, old, new = sys.argv[1:]
def walk(v):
    if isinstance(v, dict):
        return {k: walk(x) for k, x in v.items()}
    if isinstance(v, list):
        return [walk(x) for x in v]
    if isinstance(v, str) and v.startswith(old):
        return new + v[len(old):]
    return v
conf = walk(json.load(open(path)))
json.dump(conf, open(path, "w"), indent=2)
if old in json.dumps(conf):
    sys.exit(f"{path} still mentions {old}")
PY
}

serve_live() {
  OUT="$LIVE" NAME="$LIVE_NAME" PORT="$LIVE_PORT" routing/serve.sh start
}

sync_scratch_csv() {
  cp "$LIVE/fused_access.csv" data/build/fused_access.csv
}

api_notice() {
  if curl -fsS "http://127.0.0.1:$API_PORT/health" >/dev/null 2>&1; then
    echo "!! An API is running on :$API_PORT with the old fused_access.csv in memory. Restart it now (it reads $LIVE/fused_access.csv)."
  else
    echo "No API answers on :$API_PORT. When started it reads $LIVE/fused_access.csv."
  fi
}

check_unit() {
  for f in tiles.tar valhalla.json fused_access.csv; do
    [[ -f "$1/$f" ]] || { echo "$1/$f is missing" >&2; return 1; }
  done
}

swap_back() {
  rm -rf "$LIVE.swap"
  mv "$LIVE" "$LIVE.swap"
  mv "$PREV" "$LIVE"
  mv "$LIVE.swap" "$PREV"
  sync_scratch_csv
  serve_live
}

rollback() {
  check_unit "$PREV"
  check_unit "$LIVE"
  step="rollback"
  swap_back
  log_line "ROLLBACK $LIVE now holds the previous build; the rolled-back one is in $PREV"
  say "rolled back: $LIVE is the previous build again, $PREV holds the one that was live"
  api_notice
}

on_exit() {
  local rc=$?
  [[ $rc -eq 0 ]] && return
  [[ "$step" == "rollback" ]] && { echo "!! rollback failed (exit $rc); check $LIVE and $PREV by hand" >&2; return; }
  stop_staging
  echo >&2
  echo "!! refresh FAILED at step '$step' (exit $rc)" >&2
  if [[ $promoted -eq 1 ]]; then
    echo "!! the new graph was already promoted; rolling back to the previous one" >&2
    if swap_back; then
      echo "!! rolled back: $LIVE is the previous graph again" >&2
    else
      echo "!! automatic rollback failed; run routing/refresh.sh rollback" >&2
    fi
  else
    echo "!! the live graph ($LIVE, port $LIVE_PORT) and its fused_access.csv were not touched" >&2
    echo "!! the rejected build stays in $STAGE for inspection" >&2
  fi
  echo "!! docs/audit/*.md were rewritten by this run's audit; don't commit them as the live state" >&2
  log_line "FAILED step=$step exit=$rc after $((SECONDS))s"
}

preflight() {
  command -v uv >/dev/null || { echo "uv not found" >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "docker is not running" >&2; exit 1; }
  [[ -d api/node_modules ]] || { echo "api/node_modules missing; run (cd api && npm ci)" >&2; exit 1; }
  local free_kb
  free_kb=$(df -Pk "$ROOT/routing" | awk 'NR==2 {print $4}')
  (( free_kb > 6 * 1024 * 1024 )) || { echo "need about 6 GB free for the staged build, have $((free_kb / 1024)) MB" >&2; exit 1; }
}

fetch() { (cd data && uv run fetch "${fetch_args[@]+"${fetch_args[@]}"}"); }

audit() {
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  (cd data && FUSED_ACCESS_CSV="$ROOT/$STAGE/fused_access.csv" uv run audit)
}

rewrite() {
  (cd data && FUSED_ACCESS_CSV="$ROOT/$STAGE/fused_access.csv" uv run rewrite --target "$ROOT/$STAGE/routable.osm.pbf")
}

build() {
  OUT="$STAGE" PBF="$STAGE/routable.osm.pbf" CONCURRENCY="$BUILD_CONCURRENCY" routing/build.sh all
  rm -rf "$STAGE/tiles"
}

serve_staging() {
  OUT="$STAGE" NAME="$STAGE_NAME" PORT="$STAGE_PORT" routing/serve.sh start
}

regression() {
  local dir="$1" url="$2" pbf="$3"
  (cd data && VALHALLA_URL="$url" FUSED_ACCESS_CSV="$ROOT/$dir/fused_access.csv" ROUTABLE_PBF="$ROOT/$pbf" \
    uv run pytest -m valhalla -q -p no:cacheprovider) 2>&1 | tee "$dir/regression.log"
}

integration() {
  local dir="$1" url="$2"
  (cd api && NO_COLOR=1 VALHALLA_URL="$url" FUSED_ACCESS_CSV="$ROOT/$dir/fused_access.csv" npm run test:integration) 2>&1 \
    | tee "$dir/integration.log"
}

promote() {
  stop_staging
  check_unit "$STAGE"
  if [[ -d "$LIVE" ]]; then
    check_unit "$LIVE"
    rm -rf "$PREV"
    mv "$LIVE" "$PREV"
  fi
  mv "$STAGE" "$LIVE"
  promoted=1
  relocate_config "$LIVE" "$STAGE"
  serve_live
}

verify_live() {
  regression "$LIVE" "http://127.0.0.1:$LIVE_PORT" "$LIVE/routable.osm.pbf" >/dev/null
  integration "$LIVE" "http://127.0.0.1:$LIVE_PORT" >/dev/null
}

finish() {
  mv "$LIVE/routable.osm.pbf" data/build/routable.osm.pbf
  sync_scratch_csv
  promoted=0
}

summary() {
  python3 - "$LIVE" "${timings[*]}" "$SECONDS" <<'PY'
import csv, json, re, sys
from collections import Counter
from pathlib import Path
live, timings, total = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
osm = json.loads(Path("data/raw/netherlands-latest.osm.pbf.meta.json").read_text())
osm_date = re.search(r"-(\d{6})\.osm\.pbf", osm.get("url", ""))
osm_date = f"20{osm_date[1][:2]}-{osm_date[1][2:4]}-{osm_date[1][4:]}" if osm_date else osm.get("last_modified", "?")
ndw = [json.loads(p.read_text())["downloaded_at"] for p in sorted(Path("data/raw/ndw").glob("*.geojson.meta.json"))]
counts = Counter(row["status"] for row in csv.DictReader(open(live / "fused_access.csv")))
def passed(log, pattern):
    hits = re.findall(pattern, (live / log).read_text())
    return hits[-1] if hits else "?"
tiles = (live / "tiles.tar").stat().st_size
print(
    f"OSM {osm_date}, NDW {min(ndw)[:16]}Z; fused {counts['allowed']} allowed / {counts['forbidden']} forbidden /"
    f" {counts['unknown']} unknown; tiles.tar {tiles / 1e6:.0f} MB;"
    f" regression {passed('regression.log', r'(\d+) passed')} passed, api integration"
    f" {passed('integration.log', r'Tests\s+(\d+) passed')} passed; {total} s ({timings})"
)
PY
}

case "${1:-}" in
  rollback)
    trap on_exit EXIT
    rollback
    exit 0
    ;;
  --force) fetch_args=(--force) ;;
  "") fetch_args=() ;;
  *) usage ;;
esac

trap on_exit EXIT
preflight
run_step fetch fetch
run_step audit audit
run_step rewrite rewrite
run_step build build
run_step serve-staging serve_staging
run_step "gate: regression suite" regression "$STAGE" "http://127.0.0.1:$STAGE_PORT" "$STAGE/routable.osm.pbf"
run_step "gate: api integration" integration "$STAGE" "http://127.0.0.1:$STAGE_PORT"
run_step promote promote
run_step "verify live graph" verify_live
run_step finish finish
step="summary"
line="$(summary)"
log_line "OK $line"
say "refresh done: $line"
api_notice
