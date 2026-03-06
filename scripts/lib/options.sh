#!/usr/bin/env bash

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

normalize_nonnegative_int() {
  local value="$1"
  local default_value="$2"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
    return
  fi

  printf '%s' "$default_value"
}

normalize_size_mode() {
  local raw_mode="$1"
  local mode="${raw_mode,,}"

  case "$mode" in
    auto|small|medium|large)
      printf '%s' "$mode"
      return
      ;;
    *)
      printf 'auto'
      ;;
  esac
}
