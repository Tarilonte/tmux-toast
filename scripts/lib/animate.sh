#!/usr/bin/env bash

set -euo pipefail

file_path="${1-}"
type_delay="${2-0.06}"
animation_mode="${3-typewriter}"
popup_width="${4-0}"
popup_height="${5-0}"

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 1
fi

cleanup() {
  rm -f "$file_path"
}

trap cleanup EXIT

run_typewriter() {
  local content
  local length
  local index
  local current_char
  local sequence
  local next_char
  local sequence_char

  content="$(<"$file_path")"
  length="${#content}"
  index=0

  LC_ALL=C

  while (( index < length )); do
    current_char="${content:index:1}"

    if [[ "$current_char" == $'\033' ]]; then
      sequence="$current_char"
      (( index += 1 ))

      if (( index < length )); then
        next_char="${content:index:1}"
        sequence+="$next_char"
        (( index += 1 ))

        if [[ "$next_char" == '[' ]]; then
          while (( index < length )); do
            sequence_char="${content:index:1}"
            sequence+="$sequence_char"
            (( index += 1 ))

            if [[ "$sequence_char" =~ [@-~] ]]; then
              break
            fi
          done
        fi
      fi

      printf '%s' "$sequence"
      continue
    fi

    printf '%s' "$current_char"

    if [[ "$current_char" != $'\n' && "$current_char" != ' ' && "$current_char" != $'\t' ]]; then
      sleep "$type_delay"
    fi

    (( index += 1 ))
  done
}

run_slide() {
  local -a lines=()
  local -a plain_lines=()
  local offset
  local shift_left
  local frame_step=1
  local max_frames=40
  local i
  local line
  local clean_line
  local padded_line
  local frame_line
  local visible_width

  strip_ansi_line() {
    local input="$1"
    local output=""
    local j=0
    local input_len="${#input}"
    local ch

    while (( j < input_len )); do
      ch="${input:j:1}"

      if [[ "$ch" == $'\033' ]]; then
        (( j += 1 ))
        if (( j < input_len )) && [[ "${input:j:1}" == '[' ]]; then
          (( j += 1 ))
          while (( j < input_len )); do
            ch="${input:j:1}"
            (( j += 1 ))
            if [[ "$ch" =~ [@-~] ]]; then
              break
            fi
          done
        fi
        continue
      fi

      output+="$ch"
      (( j += 1 ))
    done

    printf '%s' "$output"
  }

  mapfile -t lines < "$file_path"

  if (( popup_width <= 0 )); then
    popup_width=1
  fi

  if (( popup_height <= 0 )); then
    popup_height="${#lines[@]}"
  fi

  for (( i = 0; i < popup_height; i += 1 )); do
    line=""
    if (( i < ${#lines[@]} )); then
      line="${lines[i]}"
    fi

    clean_line="$(strip_ansi_line "$line")"
    if (( ${#clean_line} < popup_width )); then
      clean_line+="$(printf '%*s' "$((popup_width - ${#clean_line}))" '')"
    fi
    plain_lines+=("${clean_line:0:popup_width}")
  done

  if (( popup_width > max_frames )); then
    frame_step=$(((popup_width + max_frames - 1) / max_frames))
  fi

  for (( offset = popup_width; offset >= 0; offset -= frame_step )); do
    printf '\033[?25l'
    printf '\033[H'

    for (( i = 0; i < popup_height; i += 1 )); do
      padded_line="${plain_lines[i]}"

      if (( offset >= popup_width )); then
        frame_line="$(printf '%*s' "$popup_width" '')"
      else
        visible_width=$((popup_width - offset))
        frame_line="$(printf '%*s' "$offset" '')${padded_line:0:visible_width}"
        if (( ${#frame_line} < popup_width )); then
          frame_line+="$(printf '%*s' "$((popup_width - ${#frame_line}))" '')"
        fi
      fi

      printf '%s' "$frame_line"
      if (( i + 1 < popup_height )); then
        printf '\n'
      fi
    done

    if (( offset > 0 )); then
      sleep "$type_delay"
    fi
  done

  printf '\033[H'
  cat "$file_path"

  sleep 2

  for (( shift_left = 0; shift_left <= popup_width; shift_left += frame_step )); do
    printf '\033[?25l'
    printf '\033[0m\033[H'

    for (( i = 0; i < popup_height; i += 1 )); do
      padded_line="${plain_lines[i]}"

      if (( shift_left >= popup_width )); then
        frame_line="$(printf '%*s' "$popup_width" '')"
      else
        frame_line="${padded_line:shift_left:popup_width}"
        if (( ${#frame_line} < popup_width )); then
          frame_line+="$(printf '%*s' "$((popup_width - ${#frame_line}))" '')"
        fi
      fi

      printf '%s' "$frame_line"
      if (( i + 1 < popup_height )); then
        printf '\n'
      fi
    done

    if (( shift_left < popup_width )); then
      sleep "$type_delay"
    fi
  done

}

case "$animation_mode" in
  slide)
    run_slide
    ;;
  *)
    run_typewriter
    ;;
esac
