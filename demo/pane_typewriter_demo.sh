#!/usr/bin/env bash

set -euo pipefail

TOAST_SCRIPT="${TOAST_SCRIPT:-$HOME/.tmux/plugins/tmux-toast/scripts/toast.sh}"

if [[ ! -x "$TOAST_SCRIPT" ]]; then
  printf 'Missing toast script: %s\n' "$TOAST_SCRIPT" >&2
  exit 1
fi

printf '$ tmux run-shell -b "%s --animation typewriter --style invert --duration 2.5 --delay 0.03 --message '\''I am a __toast__'\''"\n' "$TOAST_SCRIPT"

while [[ -z "$(tmux display-message -p '#{client_name}' 2>/dev/null)" ]]; do
  sleep 0.1
done

sleep 0.7

tmux run-shell -b "$TOAST_SCRIPT --animation typewriter --style invert --duration 2.5 --delay 0.03 --message 'I am a __toast__'"

sleep 4
