#!/usr/bin/env bash

parse_markdown_line() {
  local input="$1"
  local -n plain_ref="$2"
  local -n masks_ref="$3"

  plain_ref=""
  masks_ref=""

  local i=0
  local length="${#input}"
  local bold=0
  local italic=0
  local underline=0
  local current
  local next
  local two_chars
  local style_mask

  while (( i < length )); do
    current="${input:i:1}"

    if [[ "$current" == "\\" ]] && (( i + 1 < length )); then
      next="${input:i+1:1}"
      if [[ "$next" == "*" || "$next" == "_" || "$next" == "\\" ]]; then
        style_mask=$((bold + (italic * 2) + (underline * 4)))
        plain_ref+="$next"
        masks_ref+="$style_mask"
        (( i += 2 ))
        continue
      fi
    fi

    if (( i + 1 < length )); then
      two_chars="${input:i:2}"

      if [[ "$two_chars" == "**" ]]; then
        bold=$((1 - bold))
        (( i += 2 ))
        continue
      fi

      if [[ "$two_chars" == "__" ]]; then
        underline=$((1 - underline))
        (( i += 2 ))
        continue
      fi
    fi

    if [[ "$current" == "*" ]]; then
      italic=$((1 - italic))
      (( i += 1 ))
      continue
    fi

    style_mask=$((bold + (italic * 2) + (underline * 4)))
    plain_ref+="$current"
    masks_ref+="$style_mask"
    (( i += 1 ))
  done
}

style_sequence_for_mask() {
  local mask="$1"
  local codes=()
  local code_string

  if (( mask & 1 )); then
    codes+=("1")
  fi

  if (( mask & 2 )); then
    codes+=("3")
  fi

  if (( mask & 4 )); then
    codes+=("4")
  fi

  if (( ${#codes[@]} == 0 )); then
    printf '\033[0m'
    return
  fi

  code_string="$(IFS=';'; printf '%s' "${codes[*]}")"
  printf '\033[0;%sm' "$code_string"
}

style_line() {
  local plain="$1"
  local masks="$2"
  local output=""
  local current_mask=0
  local i
  local length="${#plain}"
  local next_mask

  for (( i = 0; i < length; i += 1 )); do
    next_mask="${masks:i:1}"
    if [[ -z "$next_mask" ]]; then
      next_mask=0
    fi

    if (( next_mask != current_mask )); then
      output+="$(style_sequence_for_mask "$next_mask")"
      current_mask="$next_mask"
    fi

    output+="${plain:i:1}"
  done

  if (( current_mask != 0 )); then
    output+=$'\033[0m'
  fi

  printf '%s' "$output"
}
