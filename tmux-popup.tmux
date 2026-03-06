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

popup_key="$(get_option "@tmux-popup-key" "P")"

tmux bind-key "$popup_key" command-prompt -p "Popup message" "run-shell \"$CURRENT_DIR/scripts/popup.sh '%%%'\""
