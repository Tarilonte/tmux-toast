#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./format.sh
source "$SCRIPT_DIR/format.sh"

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
viewport_width="${13-0}"

write_lock_file=""
fd_opened=0
write_lock_open=0
frame_width=0
frame_height=0
STYLE_PREFIX=""
STYLE_RESET=""
REDRAW_INTERVAL_MS=50
preserve_ansi_content=0
frame_has_ansi=0
TOAST_SLIDE_MIN_FRAME_DELAY='0.01'

setup_write_lock() {
  local safe_tty

  safe_tty="${client_tty//[^a-zA-Z0-9._-]/_}"
  write_lock_file="${TMPDIR:-/tmp}/tmux-toast-tty-write-${safe_tty}.lock"
  exec 9>"$write_lock_file"
  write_lock_open=1
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

is_csi_final_byte() {
  local ch="$1"
  local code

  if [[ -z "$ch" ]]; then
    return 1
  fi

  printf -v code '%d' "'$ch"
  (( code >= 64 && code <= 126 ))
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
          if is_csi_final_byte "$ch"; then
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

parse_styled_line_to_plain_masks() {
  local input="$1"
  local -n plain_ref="$2"
  local -n masks_ref="$3"
  local output_plain=""
  local output_masks=""
  local index=0
  local input_len="${#input}"
  local ch
  local final
  local sequence
  local mask=0
  local code
  local -a codes=()

  while (( index < input_len )); do
    ch="${input:index:1}"

    if [[ "$ch" == $'\033' ]]; then
      (( index += 1 ))

      if (( index < input_len )) && [[ "${input:index:1}" == '[' ]]; then
        (( index += 1 ))
        sequence=""
        final=""

        while (( index < input_len )); do
          ch="${input:index:1}"
          (( index += 1 ))
          if is_csi_final_byte "$ch"; then
            final="$ch"
            break
          fi

          sequence+="$ch"
        done

        if [[ "$final" == 'm' ]]; then
          IFS=';' read -r -a codes <<< "$sequence"
          if (( ${#codes[@]} == 0 )); then
            codes=("0")
          fi

          for code in "${codes[@]}"; do
            if [[ -z "$code" ]]; then
              code=0
            fi

            case "$code" in
              0)
                mask=0
                ;;
              1)
                mask=$((mask | 1))
                ;;
              3)
                mask=$((mask | 2))
                ;;
              4)
                mask=$((mask | 4))
                ;;
              22)
                mask=$((mask & ~1))
                ;;
              23)
                mask=$((mask & ~2))
                ;;
              24)
                mask=$((mask & ~4))
                ;;
            esac
          done
        fi
      fi

      continue
    fi

    output_plain+="$ch"
    output_masks+="$mask"
    (( index += 1 ))
  done

  plain_ref="$output_plain"
  masks_ref="$output_masks"
}

build_styled_lines_from_plain_masks() {
  local -n plain_ref="$1"
  local -n masks_ref="$2"
  local -n output_ref="$3"
  local line_plain
  local line_masks
  local styled_line
  local i

  output_ref=()
  for (( i = 0; i < text_height; i += 1 )); do
    line_plain=""
    line_masks=""

    if (( i < ${#plain_ref[@]} )); then
      line_plain="${plain_ref[i]}"
    fi

    if (( i < ${#masks_ref[@]} )); then
      line_masks="${masks_ref[i]}"
    fi

    styled_line="$(style_line "$line_plain" "$line_masks")"
    styled_line="$(restore_base_style_in_preserved_line "$styled_line")"
    output_ref+=("$styled_line")
  done
}

slice_ansi_prefix() {
  local input="$1"
  local max_columns="$2"
  local output=""
  local index=0
  local input_len="${#input}"
  local visible_columns=0
  local ch

  if (( max_columns <= 0 )); then
    return
  fi

  while (( index < input_len && visible_columns < max_columns )); do
    ch="${input:index:1}"

    if [[ "$ch" == $'\033' ]]; then
      output+="$ch"
      (( index += 1 ))
      if (( index < input_len )) && [[ "${input:index:1}" == '[' ]]; then
        output+='['
        (( index += 1 ))
        while (( index < input_len )); do
          ch="${input:index:1}"
          output+="$ch"
          (( index += 1 ))
          if is_csi_final_byte "$ch"; then
            break
          fi
        done
      fi
      continue
    fi

    output+="$ch"
    (( index += 1 ))
    (( visible_columns += 1 ))
  done

  printf '%s' "$output"
}

restore_base_style_in_preserved_line() {
  local line="$1"
  local reset_seq=$'\033[0m'
  local open_seq=$'\033[0;'
  local reset_with_base

  if [[ -z "$line" ]]; then
    return
  fi

  line="${line//$open_seq/$'\033['}"

  if [[ -n "$STYLE_PREFIX" ]]; then
    reset_with_base="${reset_seq}${STYLE_PREFIX}"
    line="${line//$reset_seq/$reset_with_base}"
  fi

  printf '%s' "$line"
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

sleep_milliseconds() {
  local milliseconds="$1"
  local seconds

  if (( milliseconds <= 0 )); then
    return
  fi

  printf -v seconds '%d.%03d' "$((milliseconds / 1000))" "$((milliseconds % 1000))"
  sleep "$seconds"
}

hold_current_frame() {
  local duration="$1"
  local duration_ms
  local end_ms
  local now_ms
  local remaining_ms
  local sleep_ms

  duration_ms="$(LC_ALL=C awk -v value="$duration" 'BEGIN {
    if (value <= 0) {
      print 0
      exit
    }
    printf "%d", (value * 1000) + 0.5
  }')"

  if (( duration_ms <= 0 )); then
    draw_current_frame
    return
  fi

  end_ms=$(( $(date +%s%3N) + duration_ms ))
  while :; do
    draw_current_frame
    now_ms="$(date +%s%3N)"
    if (( now_ms >= end_ms )); then
      break
    fi

    remaining_ms=$((end_ms - now_ms))
    if (( remaining_ms > REDRAW_INTERVAL_MS )); then
      sleep_ms="$REDRAW_INTERVAL_MS"
    else
      sleep_ms="$remaining_ms"
    fi

    sleep_milliseconds "$sleep_ms"
  done
}

clamp_toast_slide_delay() {
  local raw_delay="$1"

  LC_ALL=C awk -v value="$raw_delay" -v min_delay="$TOAST_SLIDE_MIN_FRAME_DELAY" 'BEGIN {
    if (value < min_delay) {
      printf "%.3f", min_delay
      exit
    }

    printf "%s", value
  }'
}

hold_toast_slide_frame() {
  local duration="$1"
  local duration_ms
  local end_ms
  local now_ms
  local remaining_ms
  local sleep_ms

  duration_ms="$(LC_ALL=C awk -v value="$duration" 'BEGIN {
    if (value <= 0) {
      print 0
      exit
    }
    printf "%d", (value * 1000) + 0.5
  }')"

  if (( duration_ms <= 0 )); then
    transition_frame_x "$origin_x" "$origin_x"
    return
  fi

  end_ms=$(( $(date +%s%3N) + duration_ms ))
  while :; do
    transition_frame_x "$origin_x" "$origin_x"
    now_ms="$(date +%s%3N)"
    if (( now_ms >= end_ms )); then
      break
    fi

    remaining_ms=$((end_ms - now_ms))
    if (( remaining_ms > REDRAW_INTERVAL_MS )); then
      sleep_ms="$REDRAW_INTERVAL_MS"
    else
      sleep_ms="$remaining_ms"
    fi

    sleep_milliseconds "$sleep_ms"
  done
}

compute_visible_region() {
  local x="$1"
  local width="$2"
  local visible_x="$x"
  local visible_start=0
  local visible_width="$width"

  if (( visible_width <= 0 )); then
    printf '0 0 0\n'
    return
  fi

  if (( visible_x < 0 )); then
    visible_start=$((-visible_x))
    visible_x=0
    visible_width=$((visible_width - visible_start))
  fi

  if (( visible_width <= 0 || visible_x >= viewport_width )); then
    printf '0 0 0\n'
    return
  fi

  if (( visible_x + visible_width > viewport_width )); then
    visible_width=$((viewport_width - visible_x))
  fi

  if (( visible_width <= 0 )); then
    printf '0 0 0\n'
    return
  fi

  printf '%s %s %s\n' "$visible_x" "$visible_start" "$visible_width"
}

clear_frame_at_x() {
  local x="$1"

  if (( fd_opened == 0 || frame_width <= 0 || frame_height <= 0 )); then
    return
  fi

  if (( write_lock_open == 1 )); then
    flock -x 9
  fi

  printf '\0337' >&3
  clear_frame_at_x_locked "$x"
  printf '\0338' >&3

  if (( write_lock_open == 1 )); then
    flock -u 9
  fi
}

clear_frame_at_x_locked() {
  local x="$1"
  local visible_x
  local visible_start
  local visible_width
  local blank_line
  local row
  local y

  if (( fd_opened == 0 || frame_width <= 0 || frame_height <= 0 )); then
    return
  fi

  IFS=' ' read -r visible_x visible_start visible_width < <(compute_visible_region "$x" "$frame_width")
  if (( visible_width <= 0 )); then
    return
  fi

  blank_line="$(repeat_char "$visible_width" " ")"
  for (( row = 0; row < frame_height; row += 1 )); do
    y=$((origin_y + row + 1))
    printf '\033[%d;%dH%s' "$y" "$((visible_x + 1))" "$blank_line" >&3
  done
}

draw_frame_at_x() {
  local x="$1"

  if (( write_lock_open == 1 )); then
    flock -x 9
  fi

  printf '\0337\033[?25l' >&3
  draw_frame_at_x_locked "$x"
  printf '\0338' >&3

  if (( write_lock_open == 1 )); then
    flock -u 9
  fi
}

draw_frame_at_x_locked() {
  local x="$1"
  local visible_x
  local visible_start
  local visible_width
  local y
  local i
  local line_segment

  IFS=' ' read -r visible_x visible_start visible_width < <(compute_visible_region "$x" "$frame_width")
  if (( visible_width <= 0 )); then
    return
  fi
  for (( i = 0; i < frame_height; i += 1 )); do
    y=$((origin_y + i + 1))

    if (( frame_has_ansi == 1 )) && (( visible_start == 0 )); then
      line_segment="$(slice_ansi_prefix "${FRAME_LINES[i]}" "$visible_width")"
      line_segment="$(restore_base_style_in_preserved_line "$line_segment")"
    else
      line_segment="${FRAME_LINES[i]:visible_start:visible_width}"
    fi

    printf '\033[%d;%dH' "$y" "$((visible_x + 1))" >&3
    if [[ -n "$STYLE_PREFIX" ]]; then
      printf '%s' "$STYLE_PREFIX" >&3
    fi
    printf '%s' "$line_segment" >&3
    if [[ -n "$STYLE_RESET" ]]; then
      printf '%s' "$STYLE_RESET" >&3
    fi
  done
}

transition_frame_x() {
  local from_x="$1"
  local to_x="$2"

  if (( write_lock_open == 1 )); then
    flock -x 9
  fi

  printf '\033[?25l' >&3
  if (( from_x != to_x )); then
    clear_frame_at_x_locked "$from_x"
  fi
  draw_frame_at_x_locked "$to_x"

  if [[ -n "$STYLE_RESET" ]]; then
    printf '%s' "$STYLE_RESET" >&3
  else
    printf '\033[0m' >&3
  fi

  if (( write_lock_open == 1 )); then
    flock -u 9
  fi
}

clear_frame() {
  clear_frame_at_x "$origin_x"
}

cleanup() {
  if (( fd_opened == 1 )); then
    clear_frame || true
    if (( write_lock_open == 1 )); then
      flock -x 9 || true
    fi
    printf '\033[?25h' >&3 || true
    if (( write_lock_open == 1 )); then
      flock -u 9 || true
    fi
  fi

  if [[ -n "$target_client" ]]; then
    tmux refresh-client -t "$target_client" >/dev/null 2>&1 || true
  fi

  rm -f "$file_path"

  if (( fd_opened == 1 )); then
    exec 3>&-
  fi

  if (( write_lock_open == 1 )); then
    exec 9>&-
    write_lock_open=0
  fi
}

build_content_lines() {
  local -a raw_lines=()
  local line
  local line_plain
  local line_masks
  local i

  if [[ "$animation_mode" == "toast-slide" ]]; then
    preserve_ansi_content=1
    frame_has_ansi=1
  else
    preserve_ansi_content=0
    frame_has_ansi=0
  fi

  CONTENT_LINES=()
  CONTENT_MASKS=()

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

    if (( preserve_ansi_content == 1 )); then
      if [[ -z "$line" ]]; then
        line="$(repeat_char "$text_width" " ")"
      fi
      CONTENT_LINES+=("$line")
      CONTENT_MASKS+=("$(repeat_char "$text_width" "0")")
      continue
    fi

    line_plain=""
    line_masks=""
    parse_styled_line_to_plain_masks "$line" line_plain line_masks

    if (( ${#line_plain} < text_width )); then
      line_plain+="$(repeat_char "$((text_width - ${#line_plain}))" " ")"
    fi

    if (( ${#line_masks} < text_width )); then
      line_masks+="$(repeat_char "$((text_width - ${#line_masks}))" "0")"
    fi

    CONTENT_LINES+=("${line_plain:0:text_width}")
    CONTENT_MASKS+=("${line_masks:0:text_width}")
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
  draw_frame_at_x "$origin_x"
}

run_typewriter() {
  local -a work_lines=()
  local -a work_masks=()
  local -a styled_lines=()
  local -a char_rows=()
  local -a char_cols=()
  local row
  local col
  local line
  local mask_line
  local target_mask
  local cursor

  for (( row = 0; row < text_height; row += 1 )); do
    work_lines+=("$(repeat_char "$text_width" " ")")
    work_masks+=("$(repeat_char "$text_width" "0")")
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

  frame_has_ansi=1

  for (( cursor = 0; cursor < ${#char_rows[@]}; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"

    line="${work_lines[row]}"
    work_lines[row]="${line:0:col}${CONTENT_LINES[row]:col:1}${line:col+1}"

    mask_line="${work_masks[row]}"
    target_mask="${CONTENT_MASKS[row]:col:1}"
    if [[ -z "$target_mask" ]]; then
      target_mask=0
    fi
    work_masks[row]="${mask_line:0:col}${target_mask}${mask_line:col+1}"

    build_styled_lines_from_plain_masks work_lines work_masks styled_lines
    build_frame_lines styled_lines
    draw_current_frame
    sleep "$type_delay"
  done

  build_styled_lines_from_plain_masks CONTENT_LINES CONTENT_MASKS styled_lines
  build_frame_lines styled_lines
  hold_current_frame "$toast_duration"

  for (( cursor = 0; cursor < ${#char_rows[@]}; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"

    line="${work_lines[row]}"
    work_lines[row]="${line:0:col} ${line:col+1}"

    mask_line="${work_masks[row]}"
    work_masks[row]="${mask_line:0:col}0${mask_line:col+1}"

    build_styled_lines_from_plain_masks work_lines work_masks styled_lines
    build_frame_lines styled_lines
    draw_current_frame
    sleep "$type_delay"
  done
}

run_slide() {
  local -a work_lines=()
  local -a work_masks=()
  local -a styled_lines=()
  local offset
  local shift_left
  local frame_step=1
  local max_frames=40
  local i
  local visible_width
  local mask_line

  if (( text_width > max_frames )); then
    frame_step=$(((text_width + max_frames - 1) / max_frames))
  fi

  frame_has_ansi=1

  for (( offset = text_width; offset >= 0; offset -= frame_step )); do
    work_lines=()
    work_masks=()
    for (( i = 0; i < text_height; i += 1 )); do
      if (( offset >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
        work_masks+=("$(repeat_char "$text_width" "0")")
      else
        visible_width=$((text_width - offset))

        line="$(repeat_char "$offset" " ")${CONTENT_LINES[i]:0:visible_width}"
        mask_line="$(repeat_char "$offset" "0")${CONTENT_MASKS[i]:0:visible_width}"

        if (( ${#line} < text_width )); then
          line+="$(repeat_char "$((text_width - ${#line}))" " ")"
        fi

        if (( ${#mask_line} < text_width )); then
          mask_line+="$(repeat_char "$((text_width - ${#mask_line}))" "0")"
        fi

        work_lines+=("$line")
        work_masks+=("$mask_line")
      fi
    done

    build_styled_lines_from_plain_masks work_lines work_masks styled_lines
    build_frame_lines styled_lines
    draw_current_frame

    if (( offset > 0 )); then
      sleep "$type_delay"
    fi
  done

  build_styled_lines_from_plain_masks CONTENT_LINES CONTENT_MASKS styled_lines
  build_frame_lines styled_lines
  hold_current_frame "$toast_duration"

  for (( shift_left = 0; shift_left <= text_width; shift_left += frame_step )); do
    work_lines=()
    work_masks=()
    for (( i = 0; i < text_height; i += 1 )); do
      if (( shift_left >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
        work_masks+=("$(repeat_char "$text_width" "0")")
      else
        line="${CONTENT_LINES[i]:shift_left:text_width}"
        mask_line="${CONTENT_MASKS[i]:shift_left:text_width}"

        if (( ${#line} < text_width )); then
          line+="$(repeat_char "$((text_width - ${#line}))" " ")"
        fi

        if (( ${#mask_line} < text_width )); then
          mask_line+="$(repeat_char "$((text_width - ${#mask_line}))" "0")"
        fi

        work_lines+=("$line")
        work_masks+=("$mask_line")
      fi
    done

    build_styled_lines_from_plain_masks work_lines work_masks styled_lines
    build_frame_lines styled_lines
    draw_current_frame

    if (( shift_left < text_width )); then
      sleep "$type_delay"
    fi
  done
}

run_toast_slide() {
  local start_x
  local current_x
  local previous_x
  local next_x
  local frame_step=1
  local max_frames=40
  local travel
  local frame_delay

  build_frame_lines CONTENT_LINES

  frame_delay="$(clamp_toast_slide_delay "$type_delay")"

  start_x="$viewport_width"
  if (( start_x < origin_x )); then
    start_x="$origin_x"
  fi

  travel=$((start_x - origin_x))
  if (( travel > max_frames )); then
    frame_step=$(((travel + max_frames - 1) / max_frames))
  fi

  current_x="$start_x"
  previous_x="$start_x"
  while (( current_x > origin_x )); do
    transition_frame_x "$previous_x" "$current_x"
    previous_x="$current_x"

    sleep "$frame_delay"

    current_x=$((current_x - frame_step))
    if (( current_x < origin_x )); then
      current_x="$origin_x"
    fi
  done

  if (( previous_x != origin_x )); then
    transition_frame_x "$previous_x" "$origin_x"
  fi
  hold_toast_slide_frame "$toast_duration"

  current_x="$origin_x"
  while (( current_x < viewport_width )); do
    next_x=$((current_x + frame_step))
    if (( next_x > viewport_width )); then
      next_x="$viewport_width"
    fi

    transition_frame_x "$current_x" "$next_x"

    current_x="$next_x"
    if (( current_x < viewport_width )); then
      sleep "$frame_delay"
    fi
  done

  origin_x="$viewport_width"

  if [[ -n "$target_client" ]]; then
    tmux refresh-client -t "$target_client" >/dev/null 2>&1 || true
  fi
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
if ! [[ "$viewport_width" =~ ^[0-9]+$ ]]; then
  viewport_width=0
fi

if (( origin_x < 0 )); then
  origin_x=0
fi
if (( origin_y < 0 )); then
  origin_y=0
fi
if (( viewport_width <= 0 )); then
  viewport_width="$text_width"
fi

setup_write_lock
trap cleanup EXIT INT TERM

exec 3>"$client_tty"
fd_opened=1

build_style_sequences "$popup_style"
build_content_lines

case "$animation_mode" in
  slide)
    run_slide
    ;;
  toast-slide)
    run_toast_slide
    ;;
  *)
    run_typewriter
    ;;
esac
