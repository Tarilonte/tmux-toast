#!/usr/bin/env bash

set -euo pipefail

file_path="${1-}"
type_delay="${2-0.06}"
animation_mode="${3-typewriter}"
text_width="${4-0}"
text_height="${5-0}"
toast_duration="${6-5}"
client_tty="${7-}"
origin_x="${8-0}"
origin_y="${9-0}"
toast_style_mode="${10-invert}"
popup_style="${11-}"
target_client="${12-}"

lock_file=""
fd_opened=0
frame_width=0
frame_height=0
STYLE_PREFIX=""
STYLE_RESET=""

release_lock() {
  local current_pid

  if [[ -z "$lock_file" || ! -f "$lock_file" ]]; then
    return
  fi

  current_pid=""
  if read -r current_pid < "$lock_file"; then
    if [[ "$current_pid" == "$$" ]]; then
      rm -f "$lock_file"
    fi
  fi
}

repeat_char() {
  local count="$1"
  local char="$2"
  local output=""
  local i

  if (( count <= 0 )); then
    return
  fi

  for (( i = 0; i < count; i += 1 )); do
    output+="$char"
  done

  printf '%s' "$output"
}

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

style_color_sgr() {
  local channel="$1"
  local value="$2"
  local base=38
  local default_code=39
  local rgb
  local r
  local g
  local b

  if [[ "$channel" == "bg" ]]; then
    base=48
    default_code=49
  fi

  if [[ "$value" == "default" ]]; then
    printf '%s' "$default_code"
    return
  fi

  if [[ "$value" =~ ^colour([0-9]{1,3})$ ]]; then
    printf '%s;5;%s' "$base" "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$value" =~ ^#([0-9A-Fa-f]{6})$ ]]; then
    rgb="${BASH_REMATCH[1]}"
    r=$((16#${rgb:0:2}))
    g=$((16#${rgb:2:2}))
    b=$((16#${rgb:4:2}))
    printf '%s;2;%s;%s;%s' "$base" "$r" "$g" "$b"
    return
  fi

  case "$value" in
    black) printf '%s' "$((base == 38 ? 30 : 40))" ;;
    red) printf '%s' "$((base == 38 ? 31 : 41))" ;;
    green) printf '%s' "$((base == 38 ? 32 : 42))" ;;
    yellow) printf '%s' "$((base == 38 ? 33 : 43))" ;;
    blue) printf '%s' "$((base == 38 ? 34 : 44))" ;;
    magenta) printf '%s' "$((base == 38 ? 35 : 45))" ;;
    cyan) printf '%s' "$((base == 38 ? 36 : 46))" ;;
    white) printf '%s' "$((base == 38 ? 37 : 47))" ;;
    brightblack|grey|gray) printf '%s' "$((base == 38 ? 90 : 100))" ;;
    brightred) printf '%s' "$((base == 38 ? 91 : 101))" ;;
    brightgreen) printf '%s' "$((base == 38 ? 92 : 102))" ;;
    brightyellow) printf '%s' "$((base == 38 ? 93 : 103))" ;;
    brightblue) printf '%s' "$((base == 38 ? 94 : 104))" ;;
    brightmagenta) printf '%s' "$((base == 38 ? 95 : 105))" ;;
    brightcyan) printf '%s' "$((base == 38 ? 96 : 106))" ;;
    brightwhite) printf '%s' "$((base == 38 ? 97 : 107))" ;;
  esac
}

build_style_sequences() {
  local style="$1"
  local token
  local trimmed
  local key
  local value
  local color_code
  local -a parts=()
  local -a codes=()
  local code_string

  STYLE_PREFIX=""
  STYLE_RESET=""

  if [[ -z "$style" || "$style" == "default" ]]; then
    return
  fi

  IFS=',' read -r -a parts <<< "$style"
  for token in "${parts[@]}"; do
    trimmed="${token# }"
    trimmed="${trimmed% }"

    if [[ -z "$trimmed" ]]; then
      continue
    fi

    if [[ "$trimmed" == "fg="* || "$trimmed" == "bg="* ]]; then
      key="${trimmed%%=*}"
      value="${trimmed#*=}"
      color_code="$(style_color_sgr "$key" "$value")"
      if [[ -n "$color_code" ]]; then
        codes+=("$color_code")
      fi
      continue
    fi

    case "$trimmed" in
      bold) codes+=("1") ;;
      dim) codes+=("2") ;;
      italic|italics) codes+=("3") ;;
      underscore|underline) codes+=("4") ;;
      blink) codes+=("5") ;;
      reverse) codes+=("7") ;;
      hidden) codes+=("8") ;;
      strikethrough) codes+=("9") ;;
    esac
  done

  if (( ${#codes[@]} == 0 )); then
    return
  fi

  code_string="$(IFS=';'; printf '0;%s' "${codes[*]}")"
  STYLE_PREFIX=$'\033['"$code_string"m
  STYLE_RESET=$'\033[0m'
}

clear_frame() {
  local blank_line
  local row
  local y

  if (( fd_opened == 0 || frame_width <= 0 || frame_height <= 0 )); then
    return
  fi

  blank_line="$(repeat_char "$frame_width" " ")"

  printf '\0337' >&3
  for (( row = 0; row < frame_height; row += 1 )); do
    y=$((origin_y + row + 1))
    printf '\033[%d;%dH%s' "$y" "$((origin_x + 1))" "$blank_line" >&3
  done
  printf '\0338' >&3
}

cleanup() {
  if (( fd_opened == 1 )); then
    clear_frame || true
    printf '\033[?25h' >&3 || true
  fi

  if [[ -n "$target_client" ]]; then
    tmux refresh-client -t "$target_client" >/dev/null 2>&1 || true
  fi

  rm -f "$file_path"
  release_lock

  if (( fd_opened == 1 )); then
    exec 3>&-
  fi
}

acquire_lock() {
  local safe_tty
  local old_pid=""

  safe_tty="${client_tty//[^a-zA-Z0-9._-]/_}"
  lock_file="${TMPDIR:-/tmp}/tmux-toast-tty-${safe_tty}.lock"

  if [[ -f "$lock_file" ]] && read -r old_pid < "$lock_file"; then
    if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 0.02
    fi
  fi

  printf '%s\n' "$$" > "$lock_file"
}

build_content_lines() {
  local -a raw_lines=()
  local line
  local i

  CONTENT_LINES=()

  mapfile -t raw_lines < "$file_path"
  if (( ${#raw_lines[@]} == 0 )); then
    raw_lines=("")
  fi

  if (( text_width <= 0 )); then
    text_width=1
  fi
  if (( text_height <= 0 )); then
    text_height="${#raw_lines[@]}"
  fi

  for (( i = 0; i < text_height; i += 1 )); do
    line=""
    if (( i < ${#raw_lines[@]} )); then
      line="${raw_lines[i]}"
    fi

    line="$(strip_ansi_line "$line")"
    if (( ${#line} < text_width )); then
      line+="$(repeat_char "$((text_width - ${#line}))" " ")"
    fi

    CONTENT_LINES+=("${line:0:text_width}")
  done
}

build_frame_lines() {
  local -n content_ref="$1"
  local content_line
  local i
  local horizontal

  FRAME_LINES=()
  if [[ "$toast_style_mode" == "normal" ]]; then
    horizontal="$(repeat_char "$text_width" "─")"
    FRAME_LINES+=("╭${horizontal}╮")
    for (( i = 0; i < text_height; i += 1 )); do
      content_line="${content_ref[i]}"
      FRAME_LINES+=("│${content_line}│")
    done
    FRAME_LINES+=("╰${horizontal}╯")
    frame_width=$((text_width + 2))
    frame_height=$((text_height + 2))
  else
    for (( i = 0; i < text_height; i += 1 )); do
      FRAME_LINES+=("${content_ref[i]}")
    done
    frame_width="$text_width"
    frame_height="$text_height"
  fi
}

draw_current_frame() {
  local y
  local i

  printf '\0337\033[?25l' >&3
  for (( i = 0; i < frame_height; i += 1 )); do
    y=$((origin_y + i + 1))
    printf '\033[%d;%dH' "$y" "$((origin_x + 1))" >&3
    if [[ -n "$STYLE_PREFIX" ]]; then
      printf '%s' "$STYLE_PREFIX" >&3
    fi
    printf '%s' "${FRAME_LINES[i]}" >&3
    if [[ -n "$STYLE_RESET" ]]; then
      printf '%s' "$STYLE_RESET" >&3
    fi
  done
  printf '\0338' >&3
}

run_typewriter() {
  local -a work_lines=()
  local -a char_rows=()
  local -a char_cols=()
  local row
  local col
  local line
  local cursor

  for (( row = 0; row < text_height; row += 1 )); do
    work_lines+=("$(repeat_char "$text_width" " ")")
  done

  for (( row = 0; row < text_height; row += 1 )); do
    line="${CONTENT_LINES[row]}"
    for (( col = 0; col < text_width; col += 1 )); do
      if [[ "${line:col:1}" != ' ' ]]; then
        char_rows+=("$row")
        char_cols+=("$col")
      fi
    done
  done

  for (( cursor = 0; cursor < ${#char_rows[@]}; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"
    line="${work_lines[row]}"
    work_lines[row]="${line:0:col}${CONTENT_LINES[row]:col:1}${line:col+1}"
    build_frame_lines work_lines
    draw_current_frame
    sleep "$type_delay"
  done

  sleep "$toast_duration"

  for (( cursor = 0; cursor < ${#char_rows[@]}; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"
    line="${work_lines[row]}"
    work_lines[row]="${line:0:col} ${line:col+1}"
    build_frame_lines work_lines
    draw_current_frame
    sleep "$type_delay"
  done
}

run_slide() {
  local -a work_lines=()
  local offset
  local shift_left
  local frame_step=1
  local max_frames=40
  local i
  local visible_width

  if (( text_width > max_frames )); then
    frame_step=$(((text_width + max_frames - 1) / max_frames))
  fi

  for (( offset = text_width; offset >= 0; offset -= frame_step )); do
    work_lines=()
    for (( i = 0; i < text_height; i += 1 )); do
      if (( offset >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
      else
        visible_width=$((text_width - offset))
        line="$(repeat_char "$offset" " ")${CONTENT_LINES[i]:0:visible_width}"
        if (( ${#line} < text_width )); then
          line+="$(repeat_char "$((text_width - ${#line}))" " ")"
        fi
        work_lines+=("$line")
      fi
    done
    build_frame_lines work_lines
    draw_current_frame
    if (( offset > 0 )); then
      sleep "$type_delay"
    fi
  done

  sleep "$toast_duration"

  for (( shift_left = 0; shift_left <= text_width; shift_left += frame_step )); do
    work_lines=()
    for (( i = 0; i < text_height; i += 1 )); do
      if (( shift_left >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
      else
        line="${CONTENT_LINES[i]:shift_left:text_width}"
        if (( ${#line} < text_width )); then
          line+="$(repeat_char "$((text_width - ${#line}))" " ")"
        fi
        work_lines+=("$line")
      fi
    done
    build_frame_lines work_lines
    draw_current_frame
    if (( shift_left < text_width )); then
      sleep "$type_delay"
    fi
  done
}

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 1
fi

if [[ -z "$client_tty" || ! -w "$client_tty" ]]; then
  rm -f "$file_path"
  exit 1
fi

if ! [[ "$text_width" =~ ^[0-9]+$ ]]; then
  text_width=1
fi
if ! [[ "$text_height" =~ ^[0-9]+$ ]]; then
  text_height=1
fi
if ! [[ "$origin_x" =~ ^-?[0-9]+$ ]]; then
  origin_x=0
fi
if ! [[ "$origin_y" =~ ^-?[0-9]+$ ]]; then
  origin_y=0
fi

if (( origin_x < 0 )); then
  origin_x=0
fi
if (( origin_y < 0 )); then
  origin_y=0
fi

acquire_lock
trap cleanup EXIT INT TERM

exec 3>"$client_tty"
fd_opened=1

build_style_sequences "$popup_style"
build_content_lines

case "$animation_mode" in
  slide)
    run_slide
    ;;
  *)
    run_typewriter
    ;;
esac
