#!/usr/bin/env bash

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_option() {
  local option="$1"
  local default_value="$2"
  local option_value

  option_value="$(tmux show-option -gqv "$option")"
  if [[ -n "$option_value" ]]; then
    printf '%s' "$option_value"
    return
  fi

  printf '%s' "$default_value"
}

toast_key="$(get_option "@tmux-toast-key" "P")"

tmux bind-key "$toast_key" command-prompt -p "Toast message" "run-shell -b \"$CURRENT_DIR/scripts/toast.sh '%%%'\""
