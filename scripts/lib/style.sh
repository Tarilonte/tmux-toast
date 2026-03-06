#!/usr/bin/env bash

style_get_value() {
  local style="$1"
  local key="$2"
  local token
  local parts=()

  if [[ -z "$style" || "$style" == "default" ]]; then
    return
  fi

  IFS=',' read -r -a parts <<< "$style"
  for token in "${parts[@]}"; do
    token="${token# }"
    token="${token% }"
    if [[ "$token" == "$key="* ]]; then
      printf '%s' "${token#${key}=}"
      return
    fi
  done
}

style_remove_key() {
  local style="$1"
  local key="$2"
  local token
  local parts=()
  local kept=()

  if [[ -z "$style" || "$style" == "default" ]]; then
    return
  fi

  IFS=',' read -r -a parts <<< "$style"
  for token in "${parts[@]}"; do
    token="${token# }"
    token="${token% }"
    if [[ -z "$token" || "$token" == "$key="* ]]; then
      continue
    fi
    kept+=("$token")
  done

  if (( ${#kept[@]} == 0 )); then
    return
  fi

  (IFS=','; printf '%s' "${kept[*]}")
}

style_set_key() {
  local style="$1"
  local key="$2"
  local value="$3"
  local stripped

  stripped="$(style_remove_key "$style" "$key")"

  if [[ -n "$stripped" ]]; then
    printf '%s' "${stripped},${key}=${value}"
  else
    printf '%s' "${key}=${value}"
  fi
}

invert_style_fg_bg() {
  local style="$1"
  local fg
  local bg
  local base
  local inverted

  fg="$(style_get_value "$style" "fg")"
  bg="$(style_get_value "$style" "bg")"

  if [[ -z "$fg" ]]; then
    fg="default"
  fi

  if [[ -z "$bg" ]]; then
    bg="default"
  fi

  base="$style"
  if [[ "$base" == "default" ]]; then
    base=""
  fi

  inverted="$(style_set_key "$base" "fg" "$bg")"
  inverted="$(style_set_key "$inverted" "bg" "$fg")"

  printf '%s' "$inverted"
}
