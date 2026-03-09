#!/usr/bin/env bash

set -euo pipefail

SOCKET_NAME="${1:-toast-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANE_SCRIPT="$SCRIPT_DIR/pane_typewriter_demo.sh"

cleanup() {
  tmux -L "$SOCKET_NAME" kill-server >/dev/null 2>&1 || true
}

trap cleanup EXIT

tmux -L "$SOCKET_NAME" kill-server >/dev/null 2>&1 || true
tmux -L "$SOCKET_NAME" new-session -d -s demo "bash '$PANE_SCRIPT'"

(sleep 8; tmux -L "$SOCKET_NAME" detach-client -a >/dev/null 2>&1 || true) &

tmux -L "$SOCKET_NAME" attach -t demo
