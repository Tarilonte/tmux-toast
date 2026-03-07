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

normalize_nonnegative_number() {
  local value="$1"
  local default_value="$2"

  if [[ "$value" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
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

normalize_animation_mode() {
  local raw_mode="$1"
  local mode="${raw_mode,,}"

  case "$mode" in
    typewriter|slide)
      printf '%s' "$mode"
      return
      ;;
    *)
      printf 'typewriter'
      ;;
  esac
}

normalize_toast_style_mode() {
  local raw_mode="$1"
  local mode="${raw_mode,,}"

  case "$mode" in
    invert|inverted)
      printf 'invert'
      return
      ;;
    normal)
      printf 'normal'
      return
      ;;
    *)
      printf 'invert'
      ;;
  esac
}

normalize_on_off() {
  local raw_value="$1"
  local default_value="$2"
  local value="${raw_value,,}"

  case "$value" in
    on|off)
      printf '%s' "$value"
      return
      ;;
    true|yes|1)
      printf 'on'
      return
      ;;
    false|no|0)
      printf 'off'
      return
      ;;
    *)
      printf '%s' "$default_value"
      ;;
  esac
}
