#!/usr/bin/env bash

set -euo pipefail

file_path="${1-}"
type_delay="${2-0.06}"
animation_mode="${3-typewriter}"
popup_width="${4-0}"
popup_height="${5-0}"
toast_duration="${6-2}"

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 1
fi

cleanup() {
  rm -f "$file_path"
}

trap cleanup EXIT

strip_ansi_line() {
  local input="$1"
  local output=""
  local index=0
  local input_len="${#input}"
  local ch

  while (( index < input_len )); do
    ch="${input:index:1}"

    if [[ "$ch" == $'\033' ]]; then
      (( index += 1 ))
      if (( index < input_len )) && [[ "${input:index:1}" == '[' ]]; then
        (( index += 1 ))
        while (( index < input_len )); do
          ch="${input:index:1}"
          (( index += 1 ))
          if [[ "$ch" =~ [@-~] ]]; then
            break
          fi
        done
      fi
      continue
    fi

    output+="$ch"
    (( index += 1 ))
  done

  printf '%s' "$output"
}

build_plain_lines() {
  local -n output_ref="$1"
  local -a raw_lines=()
  local i
  local line

  output_ref=()
  mapfile -t raw_lines < "$file_path"

  if (( ${#raw_lines[@]} == 0 )); then
    raw_lines=("")
  fi

  if (( popup_width <= 0 )); then
    popup_width=1
  fi

  if (( popup_height <= 0 )); then
    popup_height="${#raw_lines[@]}"
  fi

  for (( i = 0; i < popup_height; i += 1 )); do
    line=""
    if (( i < ${#raw_lines[@]} )); then
      line="${raw_lines[i]}"
    fi

    line="$(strip_ansi_line "$line")"
    if (( ${#line} < popup_width )); then
      line+="$(printf '%*s' "$((popup_width - ${#line}))" '')"
    fi

    output_ref+=("${line:0:popup_width}")
  done
}

draw_lines() {
  local -n lines_ref="$1"
  local i

  printf '\033[?25l\033[H'
  for (( i = 0; i < popup_height; i += 1 )); do
    printf '%s' "${lines_ref[i]}"
    if (( i + 1 < popup_height )); then
      printf '\n'
    fi
  done
}

run_typewriter() {
  local content
  local length
  local index
  local current_char
  local sequence
  local next_char
  local sequence_char
  local -a plain_lines=()
  local -a char_rows=()
  local -a char_cols=()
  local row
  local col
  local line
  local cursor

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

  sleep "$toast_duration"

  build_plain_lines plain_lines

  for (( row = 0; row < popup_height; row += 1 )); do
    line="${plain_lines[row]}"
    for (( col = 0; col < popup_width; col += 1 )); do
      if [[ "${line:col:1}" != ' ' ]]; then
        char_rows+=("$row")
        char_cols+=("$col")
      fi
    done
  done

  for (( cursor = 0; cursor < ${#char_rows[@]}; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"
    line="${plain_lines[row]}"
    plain_lines[row]="${line:0:col} ${line:col+1}"
    draw_lines plain_lines
    sleep "$type_delay"
  done
}

run_slide() {
  local -a plain_lines=()
  local -a frame_lines=()
  local offset
  local shift_left
  local frame_step=1
  local max_frames=40
  local i
  local padded_line
  local frame_line
  local visible_width

  build_plain_lines plain_lines

  if (( popup_width > max_frames )); then
    frame_step=$(((popup_width + max_frames - 1) / max_frames))
  fi

  for (( offset = popup_width; offset >= 0; offset -= frame_step )); do
    frame_lines=()

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

      frame_lines+=("$frame_line")
    done

    draw_lines frame_lines

    if (( offset > 0 )); then
      sleep "$type_delay"
    fi
  done

  printf '\033[H'
  cat "$file_path"

  sleep "$toast_duration"

  for (( shift_left = 0; shift_left <= popup_width; shift_left += frame_step )); do
    frame_lines=()

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

      frame_lines+=("$frame_line")
    done

    draw_lines frame_lines

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
