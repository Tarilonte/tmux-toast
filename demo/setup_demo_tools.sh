#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGG_BIN="$ROOT_DIR/tools/bin/agg"
AGG_URL="https://github.com/asciinema/agg/releases/download/v1.7.0/agg-x86_64-unknown-linux-gnu"

if ! command -v asciinema >/dev/null 2>&1; then
  python3 -m pip install --user --break-system-packages asciinema
fi

if [[ ! -x "$AGG_BIN" ]]; then
  mkdir -p "$ROOT_DIR/tools/bin"
  curl -fsSL "$AGG_URL" -o "$AGG_BIN"
  chmod +x "$AGG_BIN"
fi

printf 'asciinema: %s\n' "$(command -v asciinema)"
printf 'agg: %s\n' "$AGG_BIN"
