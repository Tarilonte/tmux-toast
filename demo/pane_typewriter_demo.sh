#!/usr/bin/env bash

set -euo pipefail

TOAST_SCRIPT="${TOAST_SCRIPT:-$HOME/.tmux/plugins/tmux-toast/scripts/toast.sh}"

if [[ ! -x "$TOAST_SCRIPT" ]]; then
  printf 'Missing toast script: %s\n' "$TOAST_SCRIPT" >&2
  exit 1
fi

printf '$ tmux run-shell -b "%s --animation none --style invert --duration 3.8 --message '\''none: __toast__'\''"\n' "$TOAST_SCRIPT"
printf '$ tmux run-shell -b "%s --animation typewriter --style invert --duration 3.8 --delay 0.03 --message '\''typewriter: __toast__'\''"\n' "$TOAST_SCRIPT"
printf '$ tmux run-shell -b "%s --animation slide --style invert --duration 3.8 --delay 0.02 --message '\''slide: __toast__'\''"\n' "$TOAST_SCRIPT"

while [[ -z "$(tmux display-message -p '#{client_name}' 2>/dev/null)" ]]; do
  sleep 0.1
done

sleep 0.7

tmux run-shell -b "$TOAST_SCRIPT --animation none --style invert --duration 3.8 --message 'none: __toast__'"
sleep 0.25

tmux run-shell -b "$TOAST_SCRIPT --animation typewriter --style invert --duration 3.8 --delay 0.03 --message 'typewriter: __toast__'"
sleep 0.25

tmux run-shell -b "$TOAST_SCRIPT --animation slide --style invert --duration 3.8 --delay 0.02 --message 'slide: __toast__'"

sleep 6
