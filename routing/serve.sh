#!/usr/bin/env bash
set -euo pipefail

IMAGE="${VALHALLA_IMAGE:-ghcr.io/valhalla/valhalla:3.9.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-routing/build/nl}"
NAME="${NAME:-naviscoot-valhalla}"
PORT="${PORT:-8002}"

case "${1:-start}" in
  start)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -p "127.0.0.1:$PORT:8002" -v "$ROOT:/repo:ro" "$IMAGE" \
      valhalla_service "/repo/$OUT/valhalla.json" "$(getconf _NPROCESSORS_ONLN)" >/dev/null
    for _ in $(seq 1 60); do
      if curl -fsS "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
        echo "valhalla up on http://127.0.0.1:$PORT ($OUT)"
        exit 0
      fi
      sleep 1
    done
    docker logs "$NAME" >&2
    echo "valhalla did not come up" >&2
    exit 1
    ;;
  stop)
    docker rm -f "$NAME" >/dev/null
    ;;
  *)
    echo "usage: routing/serve.sh start|stop  (env: OUT NAME PORT)" >&2
    exit 2
    ;;
esac
