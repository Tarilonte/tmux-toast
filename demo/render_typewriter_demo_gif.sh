#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_DIR="$ROOT_DIR/demo"
ASSETS_DIR="$ROOT_DIR/assets"

ASCIINEMA_BIN="${ASCIINEMA_BIN:-$(command -v asciinema || true)}"
AGG_BIN="${AGG_BIN:-$ROOT_DIR/tools/bin/agg}"

CAST_FILE="$DEMO_DIR/tmux-toast-typewriter.cast"
GIF_FILE="$ASSETS_DIR/tmux-toast-typewriter.gif"

if [[ ! -x "$ASCIINEMA_BIN" ]]; then
  printf 'Missing asciinema binary: %s\n' "$ASCIINEMA_BIN" >&2
  exit 1
fi

if [[ ! -x "$AGG_BIN" ]]; then
  printf 'Missing agg binary: %s\n' "$AGG_BIN" >&2
  exit 1
fi

mkdir -p "$ASSETS_DIR"

"$ASCIINEMA_BIN" rec \
  --overwrite \
  --yes \
  --quiet \
  --cols 100 \
  --rows 24 \
  --idle-time-limit 1 \
  -c "$DEMO_DIR/run_typewriter_demo_session.sh toast-demo" \
  "$CAST_FILE"

"$AGG_BIN" \
  --cols 100 \
  --rows 24 \
  --font-size 16 \
  --idle-time-limit 1 \
  --last-frame-duration 1 \
  --theme nord \
  "$CAST_FILE" \
  "$GIF_FILE"

printf 'Generated %s\n' "$GIF_FILE"
