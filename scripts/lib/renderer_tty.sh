#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./format.sh
source "$SCRIPT_DIR/format.sh"

client_name="${1-}"
client_tty="${2-}"
state_dir="${3-}"

TOAST_STACK_GAP=1
IDLE_EXIT_MS=1500

declare -A TOAST_MODE
declare -A TOAST_DELAY_MS
declare -A TOAST_DURATION_MS
declare -A TOAST_CREATED_MS
declare -A TOAST_TEXT_WIDTH
declare -A TOAST_TEXT_HEIGHT
declare -A TOAST_STYLE_MODE
declare -A TOAST_POPUP_STYLE
declare -A TOAST_PREFIX
declare -A TOAST_RESET
declare -A TOAST_MESSAGE_FILE
declare -A TOAST_CHAR_COUNT
declare -A TOAST_STEP_COUNT
declare -A TOAST_FRAME_STEP
declare -A TOAST_FRAME_WIDTH
declare -A TOAST_FRAME_HEIGHT

declare -A PREV_ROW_X
declare -A PREV_ROW_WIDTH
declare -A PREV_ROW_TEXT
declare -A CURR_ROW_X
declare -A CURR_ROW_WIDTH
declare -A CURR_ROW_TEXT

active_toast_ids=()
renderer_margin_top=-1
renderer_margin_right=-1
previous_min_row=-1
previous_max_row=-1
current_min_row=-1
current_max_row=-1
idle_since_ms=0

write_lock_file=""
write_lock_open=0
fd_opened=0
wake_requested=0

request_dir="$state_dir/requests"
message_dir="$state_dir/messages"
pid_file="$state_dir/renderer.pid"
start_lock_file="$state_dir/renderer.lock"

cleanup() {
  local row

  if (( fd_opened == 1 && previous_min_row >= 0 && previous_max_row >= previous_min_row )); then
    acquire_write_lock || true
    printf '\0337' >&3 || true
    for (( row = previous_min_row; row <= previous_max_row; row += 1 )); do
      if [[ -n "${PREV_ROW_WIDTH[$row]-}" && -n "${PREV_ROW_X[$row]-}" ]]; then
        clear_row_segment "$row" "${PREV_ROW_X[$row]}" "${PREV_ROW_WIDTH[$row]}" || true
      fi
    done
    printf '\0338\033[?25h' >&3 || true
    release_write_lock || true
  fi

  rm -f "$pid_file"

  if (( fd_opened == 1 )); then
    exec 3>&-
  fi

  if (( write_lock_open == 1 )); then
    exec 9>&-
    write_lock_open=0
  fi
}

trap cleanup EXIT INT TERM
trap 'wake_requested=1' USR1

if [[ -z "$client_name" || -z "$client_tty" || -z "$state_dir" ]]; then
  exit 1
fi

if [[ ! -d "$request_dir" || ! -d "$message_dir" ]]; then
  exit 1
fi

if [[ ! -w "$client_tty" ]]; then
  exit 1
fi

printf '%s\n' "$$" > "$pid_file"

exec 3>"$client_tty"
fd_opened=1

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

spaces() {
  local count="$1"

  if (( count <= 0 )); then
    return
  fi

  printf '%*s' "$count" ''
}

clamp() {
  local value="$1"
  local min_value="$2"
  local max_value="$3"

  if (( value < min_value )); then
    printf '%s' "$min_value"
    return
  fi

  if (( value > max_value )); then
    printf '%s' "$max_value"
    return
  fi

  printf '%s' "$value"
}

now_ms() {
  date +%s%3N
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

build_style_sequences_for() {
  local style="$1"
  local -n prefix_ref="$2"
  local -n reset_ref="$3"
  local token
  local trimmed
  local key
  local value
  local color_code
  local -a parts=()
  local -a codes=()
  local code_string

  prefix_ref=""
  reset_ref=""

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
  prefix_ref=$'\033['"$code_string"m
  reset_ref=$'\033[0m'
}

restore_base_style_in_line() {
  local line="$1"
  local prefix="$2"
  local reset_seq=$'\033[0m'
  local open_seq=$'\033[0;'
  local reset_with_base

  if [[ -z "$line" ]]; then
    return
  fi

  line="${line//$open_seq/$'\033['}"

  if [[ -n "$prefix" ]]; then
    reset_with_base="${reset_seq}${prefix}"
    line="${line//$reset_seq/$reset_with_base}"
  fi

  printf '%s' "$line"
}

style_line_with_base() {
  local plain="$1"
  local masks="$2"
  local prefix="$3"
  local line

  line="$(style_line "$plain" "$masks")"
  restore_base_style_in_line "$line" "$prefix"
}

sanitize_toast_id() {
  local raw="$1"
  raw="${raw//[^a-zA-Z0-9_]/_}"
  if [[ -z "$raw" ]]; then
    raw="toast"
  fi
  printf '%s' "$raw"
}

store_array_var() {
  local var_name="$1"
  shift
  local serialized='('
  local value
  local quoted

  for value in "$@"; do
    printf -v quoted '%q' "$value"
    serialized+=" $quoted"
  done

  serialized+=' )'
  eval "$var_name=$serialized"
}

unset_toast_array_vars() {
  local toast_id="$1"
  unset "toast_${toast_id}_content_lines"
  unset "toast_${toast_id}_content_masks"
  unset "toast_${toast_id}_full_styled_lines"
  unset "toast_${toast_id}_full_frame_lines"
  unset "toast_${toast_id}_char_rows"
  unset "toast_${toast_id}_char_cols"
}

list_client_metrics() {
  tmux list-clients -F '#{client_name}	#{client_width}	#{client_height}	#{client_tty}' 2>/dev/null || true
}

refresh_client_geometry() {
  local line
  local name
  local width
  local height
  local tty

  renderer_client_width=""
  renderer_client_height=""

  while IFS=$'\t' read -r name width height tty; do
    if [[ "$name" == "$client_name" ]]; then
      renderer_client_width="$width"
      renderer_client_height="$height"
      if [[ -n "$tty" ]]; then
        client_tty="$tty"
      fi
      break
    fi
  done < <(list_client_metrics)

  if [[ -z "$renderer_client_width" || -z "$renderer_client_height" ]]; then
    return 1
  fi

  if ! [[ "$renderer_client_width" =~ ^[0-9]+$ && "$renderer_client_height" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  return 0
}

setup_write_lock() {
  local safe_tty

  safe_tty="${client_tty//[^a-zA-Z0-9._-]/_}"
  write_lock_file="${TMPDIR:-/tmp}/tmux-toast-tty-write-${safe_tty}.lock"
  exec 9>"$write_lock_file"
  write_lock_open=1
}

acquire_write_lock() {
  if (( write_lock_open == 0 )); then
    return 1
  fi

  flock -x 9
}

release_write_lock() {
  if (( write_lock_open == 0 )); then
    return 1
  fi

  flock -u 9
}

clear_row_segment() {
  local row="$1"
  local x="$2"
  local width="$3"

  if (( width <= 0 || x < 0 )); then
    return
  fi

  printf '\033[%d;%dH%s' "$((row + 1))" "$((x + 1))" "$(spaces "$width")" >&3
}

render_row_segment() {
  local row="$1"
  local x="$2"
  local text="$3"

  printf '\033[%d;%dH%s' "$((row + 1))" "$((x + 1))" "$text" >&3
}

clear_current_row_maps() {
  CURR_ROW_X=()
  CURR_ROW_WIDTH=()
  CURR_ROW_TEXT=()
  current_min_row=-1
  current_max_row=-1
}

copy_current_rows_to_previous() {
  PREV_ROW_X=()
  PREV_ROW_WIDTH=()
  PREV_ROW_TEXT=()

  local row
  for row in "${!CURR_ROW_TEXT[@]}"; do
    PREV_ROW_X[$row]="${CURR_ROW_X[$row]}"
    PREV_ROW_WIDTH[$row]="${CURR_ROW_WIDTH[$row]}"
    PREV_ROW_TEXT[$row]="${CURR_ROW_TEXT[$row]}"
  done

  previous_min_row="$current_min_row"
  previous_max_row="$current_max_row"
}

register_row_segment() {
  local row="$1"
  local x="$2"
  local width="$3"
  local text="$4"

  CURR_ROW_X[$row]="$x"
  CURR_ROW_WIDTH[$row]="$width"
  CURR_ROW_TEXT[$row]="$text"

  if (( current_min_row < 0 || row < current_min_row )); then
    current_min_row="$row"
  fi

  if (( current_max_row < 0 || row > current_max_row )); then
    current_max_row="$row"
  fi
}

render_changed_rows() {
  local start_row
  local end_row
  local row
  local prev_text
  local curr_text
  local prev_x
  local curr_x
  local prev_width
  local curr_width

  if (( previous_min_row < 0 && current_min_row < 0 )); then
    return
  fi

  if (( previous_min_row < 0 )); then
    start_row="$current_min_row"
  elif (( current_min_row < 0 )); then
    start_row="$previous_min_row"
  elif (( previous_min_row < current_min_row )); then
    start_row="$previous_min_row"
  else
    start_row="$current_min_row"
  fi

  if (( previous_max_row > current_max_row )); then
    end_row="$previous_max_row"
  else
    end_row="$current_max_row"
  fi

  acquire_write_lock
  printf '\0337' >&3

  for (( row = start_row; row <= end_row; row += 1 )); do
    prev_text="${PREV_ROW_TEXT[$row]-}"
    curr_text="${CURR_ROW_TEXT[$row]-}"
    prev_x="${PREV_ROW_X[$row]-}"
    curr_x="${CURR_ROW_X[$row]-}"
    prev_width="${PREV_ROW_WIDTH[$row]-0}"
    curr_width="${CURR_ROW_WIDTH[$row]-0}"

    if [[ "$prev_text" == "$curr_text" && "$prev_x" == "$curr_x" && "$prev_width" == "$curr_width" ]]; then
      continue
    fi

    if [[ -n "$prev_text" && -n "$prev_x" ]] && (( prev_width > 0 )); then
      clear_row_segment "$row" "$prev_x" "$prev_width"
    fi

    if [[ -n "$curr_text" && -n "$curr_x" ]] && (( curr_width > 0 )); then
      render_row_segment "$row" "$curr_x" "$curr_text"
    fi
  done

  printf '\0338' >&3
  release_write_lock

  copy_current_rows_to_previous
}

build_frame_lines_for_style() {
  local text_width="$1"
  local text_height="$2"
  local style_mode="$3"
  local prefix="$4"
  local reset="$5"
  local -n content_ref="$6"
  local -n output_ref="$7"
  local -n frame_width_ref="$8"
  local -n frame_height_ref="$9"
  local horizontal
  local row

  output_ref=()

  if [[ "$style_mode" == "normal" ]]; then
    horizontal="$(repeat_char "$text_width" "─")"
    output_ref+=("${prefix}╭${horizontal}╮${reset}")
    for (( row = 0; row < text_height; row += 1 )); do
      output_ref+=("${prefix}│${content_ref[row]}│${reset}")
    done
    output_ref+=("${prefix}╰${horizontal}╯${reset}")
    frame_width_ref=$((text_width + 2))
    frame_height_ref=$((text_height + 2))
  else
    for (( row = 0; row < text_height; row += 1 )); do
      output_ref+=("${prefix}${content_ref[row]}${reset}")
    done
    frame_width_ref="$text_width"
    frame_height_ref="$text_height"
  fi
}

load_request() {
  local request_file="$1"
  local request_id
  local message_file
  local animation_mode
  local delay_ms
  local duration_ms
  local text_width
  local text_height
  local toast_style_mode
  local popup_style
  local margin_top
  local margin_right
  local created_ms
  local toast_id
  local prefix
  local reset
  local -a raw_lines=()
  local -a content_lines=()
  local -a content_masks=()
  local -a full_styled_lines=()
  local -a full_frame_lines=()
  local -a char_rows=()
  local -a char_cols=()
  local line
  local line_plain
  local line_masks
  local styled_line
  local row
  local col
  local frame_width
  local frame_height
  local frame_step=1
  local step_count=0

  # shellcheck disable=SC1090
  source "$request_file"

  toast_id="$(sanitize_toast_id "$request_id")"

  build_style_sequences_for "$popup_style" prefix reset

  mapfile -t raw_lines < "$message_file"
  if (( ${#raw_lines[@]} == 0 )); then
    raw_lines=("")
  fi

  if (( text_width <= 0 )); then
    text_width=1
  fi
  if (( text_height <= 0 )); then
    text_height="${#raw_lines[@]}"
  fi

  for (( row = 0; row < text_height; row += 1 )); do
    line=""
    if (( row < ${#raw_lines[@]} )); then
      line="${raw_lines[row]}"
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

    content_lines+=("${line_plain:0:text_width}")
    content_masks+=("${line_masks:0:text_width}")
  done

  for (( row = 0; row < text_height; row += 1 )); do
    styled_line="$(style_line_with_base "${content_lines[row]}" "${content_masks[row]}" "$prefix")"
    full_styled_lines+=("$styled_line")
  done

  build_frame_lines_for_style "$text_width" "$text_height" "$toast_style_mode" "$prefix" "$reset" full_styled_lines full_frame_lines frame_width frame_height

  if [[ "$animation_mode" == "typewriter" ]]; then
    for (( row = 0; row < text_height; row += 1 )); do
      line="${content_lines[row]}"
      for (( col = 0; col < text_width; col += 1 )); do
        if [[ "${line:col:1}" != ' ' ]]; then
          char_rows+=("$row")
          char_cols+=("$col")
        fi
      done
    done
  elif [[ "$animation_mode" == "slide" ]]; then
    if (( text_width > 40 )); then
      frame_step=$(((text_width + 39) / 40))
    fi
    step_count=$(((text_width + frame_step - 1) / frame_step))
  fi

  TOAST_MODE[$toast_id]="$animation_mode"
  TOAST_DELAY_MS[$toast_id]="$delay_ms"
  TOAST_DURATION_MS[$toast_id]="$duration_ms"
  TOAST_CREATED_MS[$toast_id]="$created_ms"
  TOAST_TEXT_WIDTH[$toast_id]="$text_width"
  TOAST_TEXT_HEIGHT[$toast_id]="$text_height"
  TOAST_STYLE_MODE[$toast_id]="$toast_style_mode"
  TOAST_POPUP_STYLE[$toast_id]="$popup_style"
  TOAST_PREFIX[$toast_id]="$prefix"
  TOAST_RESET[$toast_id]="$reset"
  TOAST_MESSAGE_FILE[$toast_id]="$message_file"
  TOAST_FRAME_WIDTH[$toast_id]="$frame_width"
  TOAST_FRAME_HEIGHT[$toast_id]="$frame_height"
  TOAST_CHAR_COUNT[$toast_id]="${#char_rows[@]}"
  TOAST_FRAME_STEP[$toast_id]="$frame_step"
  TOAST_STEP_COUNT[$toast_id]="$step_count"

  store_array_var "toast_${toast_id}_content_lines" "${content_lines[@]}"
  store_array_var "toast_${toast_id}_content_masks" "${content_masks[@]}"
  store_array_var "toast_${toast_id}_full_styled_lines" "${full_styled_lines[@]}"
  store_array_var "toast_${toast_id}_full_frame_lines" "${full_frame_lines[@]}"
  store_array_var "toast_${toast_id}_char_rows" "${char_rows[@]}"
  store_array_var "toast_${toast_id}_char_cols" "${char_cols[@]}"

  if (( ${#active_toast_ids[@]} == 0 )); then
    renderer_margin_top="$margin_top"
    renderer_margin_right="$margin_right"
  fi

  rm -f "$request_file"
  active_toast_ids+=("$toast_id")
}

remove_toast() {
  local toast_id="$1"
  local kept_ids=()
  local current_id

  rm -f "${TOAST_MESSAGE_FILE[$toast_id]-}" || true

  unset 'TOAST_MODE[$toast_id]'
  unset 'TOAST_DELAY_MS[$toast_id]'
  unset 'TOAST_DURATION_MS[$toast_id]'
  unset 'TOAST_CREATED_MS[$toast_id]'
  unset 'TOAST_TEXT_WIDTH[$toast_id]'
  unset 'TOAST_TEXT_HEIGHT[$toast_id]'
  unset 'TOAST_STYLE_MODE[$toast_id]'
  unset 'TOAST_POPUP_STYLE[$toast_id]'
  unset 'TOAST_PREFIX[$toast_id]'
  unset 'TOAST_RESET[$toast_id]'
  unset 'TOAST_MESSAGE_FILE[$toast_id]'
  unset 'TOAST_FRAME_WIDTH[$toast_id]'
  unset 'TOAST_FRAME_HEIGHT[$toast_id]'
  unset 'TOAST_CHAR_COUNT[$toast_id]'
  unset 'TOAST_FRAME_STEP[$toast_id]'
  unset 'TOAST_STEP_COUNT[$toast_id]'
  unset_toast_array_vars "$toast_id"

  for current_id in "${active_toast_ids[@]}"; do
    if [[ "$current_id" != "$toast_id" ]]; then
      kept_ids+=("$current_id")
    fi
  done
  active_toast_ids=("${kept_ids[@]}")

  if (( ${#active_toast_ids[@]} == 0 )); then
    renderer_margin_top=-1
    renderer_margin_right=-1
  fi
}

toast_total_duration_ms() {
  local toast_id="$1"
  local mode="${TOAST_MODE[$toast_id]}"
  local delay_ms="${TOAST_DELAY_MS[$toast_id]}"
  local hold_ms="${TOAST_DURATION_MS[$toast_id]}"
  local enter_ms=0
  local exit_ms=0

  case "$mode" in
    typewriter)
      enter_ms=$(( TOAST_CHAR_COUNT[$toast_id] * delay_ms ))
      exit_ms="$enter_ms"
      ;;
    slide)
      enter_ms=$(( TOAST_STEP_COUNT[$toast_id] * delay_ms ))
      exit_ms="$enter_ms"
      ;;
  esac

  printf '%s' $((enter_ms + hold_ms + exit_ms))
}

toast_is_expired() {
  local toast_id="$1"
  local current_ms="$2"
  local created_ms="${TOAST_CREATED_MS[$toast_id]}"
  local total_ms

  total_ms="$(toast_total_duration_ms "$toast_id")"
  (( current_ms - created_ms >= total_ms ))
}

toast_next_due_ms() {
  local toast_id="$1"
  local mode="${TOAST_MODE[$toast_id]}"
  local delay_ms="${TOAST_DELAY_MS[$toast_id]}"
  local hold_ms="${TOAST_DURATION_MS[$toast_id]}"
  local created_ms="${TOAST_CREATED_MS[$toast_id]}"
  local char_count="${TOAST_CHAR_COUNT[$toast_id]-0}"
  local step_count="${TOAST_STEP_COUNT[$toast_id]-0}"
  local enter_ms=0
  local exit_ms=0
  local total_ms=0
  local elapsed_ms
  local phase_end_ms
  local exit_elapsed

  elapsed_ms="$(( $(now_ms) - created_ms ))"

  case "$mode" in
    none)
      printf '%s' "$((created_ms + hold_ms))"
      return
      ;;
    typewriter)
      enter_ms=$(( char_count * delay_ms ))
      exit_ms="$enter_ms"
      ;;
    slide)
      enter_ms=$(( step_count * delay_ms ))
      exit_ms="$enter_ms"
      ;;
  esac

  total_ms=$((enter_ms + hold_ms + exit_ms))

  if (( delay_ms <= 0 )); then
    printf '%s' "$((created_ms + total_ms))"
    return
  fi

  if (( elapsed_ms < enter_ms )) && (( delay_ms > 0 )); then
      printf '%s' "$((created_ms + (((elapsed_ms / delay_ms) + 1) * delay_ms)))"
    return
  fi

  if (( elapsed_ms < enter_ms + hold_ms )); then
    phase_end_ms=$((created_ms + enter_ms + hold_ms))
    printf '%s' "$phase_end_ms"
    return
  fi

  if (( elapsed_ms < total_ms )) && (( delay_ms > 0 )); then
    exit_elapsed=$((elapsed_ms - enter_ms - hold_ms))
    printf '%s' "$((created_ms + enter_ms + hold_ms + (((exit_elapsed / delay_ms) + 1) * delay_ms)))"
    return
  fi

  printf '%s' "$((created_ms + total_ms))"
}

load_named_array() {
  local var_name="$1"
  local -n output_ref="$2"
  local -n named_ref="$var_name"
  output_ref=("${named_ref[@]}")
}

build_typewriter_frame() {
  local toast_id="$1"
  local elapsed_ms="$2"
  local -n output_ref="$3"
  local -a content_lines=()
  local -a content_masks=()
  local -a char_rows=()
  local -a char_cols=()
  local -a work_lines=()
  local -a work_masks=()
  local -a styled_lines=()
  local row
  local col
  local start_index=0
  local end_index=0
  local enter_ms=$(( TOAST_CHAR_COUNT[$toast_id] * TOAST_DELAY_MS[$toast_id] ))
  local hold_end_ms=$(( enter_ms + TOAST_DURATION_MS[$toast_id] ))
  local delay_ms="${TOAST_DELAY_MS[$toast_id]}"
  local char_count="${TOAST_CHAR_COUNT[$toast_id]}"
  local cursor
  local line
  local mask_line
  local target_mask
  local -a frame_lines=()
  local frame_width
  local frame_height

  load_named_array "toast_${toast_id}_content_lines" content_lines
  load_named_array "toast_${toast_id}_content_masks" content_masks
  load_named_array "toast_${toast_id}_char_rows" char_rows
  load_named_array "toast_${toast_id}_char_cols" char_cols

  for (( row = 0; row < TOAST_TEXT_HEIGHT[$toast_id]; row += 1 )); do
    work_lines+=("$(repeat_char "${TOAST_TEXT_WIDTH[$toast_id]}" " ")")
    work_masks+=("$(repeat_char "${TOAST_TEXT_WIDTH[$toast_id]}" "0")")
  done

  if (( delay_ms <= 0 )); then
    if (( elapsed_ms < hold_end_ms )); then
      start_index=0
      end_index="$char_count"
    else
      start_index="$char_count"
      end_index="$char_count"
    fi
  elif (( elapsed_ms < enter_ms )); then
    start_index=0
    end_index=$(( (elapsed_ms / delay_ms) + 1 ))
    if (( end_index > char_count )); then
      end_index="$char_count"
    fi
  elif (( elapsed_ms < hold_end_ms )); then
    start_index=0
    end_index="$char_count"
  else
    start_index=$(( ((elapsed_ms - hold_end_ms) / delay_ms) + 1 ))
    if (( start_index > char_count )); then
      start_index="$char_count"
    fi
    end_index="$char_count"
  fi

  for (( cursor = start_index; cursor < end_index; cursor += 1 )); do
    row="${char_rows[cursor]}"
    col="${char_cols[cursor]}"
    line="${work_lines[row]}"
    work_lines[row]="${line:0:col}${content_lines[row]:col:1}${line:col+1}"
    mask_line="${work_masks[row]}"
    target_mask="${content_masks[row]:col:1}"
    if [[ -z "$target_mask" ]]; then
      target_mask=0
    fi
    work_masks[row]="${mask_line:0:col}${target_mask}${mask_line:col+1}"
  done

  build_styled_lines_for_toast "$toast_id" work_lines work_masks styled_lines
  build_frame_lines_for_style "${TOAST_TEXT_WIDTH[$toast_id]}" "${TOAST_TEXT_HEIGHT[$toast_id]}" "${TOAST_STYLE_MODE[$toast_id]}" "${TOAST_PREFIX[$toast_id]}" "${TOAST_RESET[$toast_id]}" styled_lines frame_lines frame_width frame_height
  output_ref=("${frame_lines[@]}")
}

build_styled_lines_for_toast() {
  local toast_id="$1"
  local -n plain_ref="$2"
  local -n masks_ref="$3"
  local -n output_ref="$4"
  local row
  local styled_line

  output_ref=()
  for (( row = 0; row < TOAST_TEXT_HEIGHT[$toast_id]; row += 1 )); do
    styled_line="$(style_line_with_base "${plain_ref[row]}" "${masks_ref[row]}" "${TOAST_PREFIX[$toast_id]}")"
    output_ref+=("$styled_line")
  done
}

build_slide_frame() {
  local toast_id="$1"
  local elapsed_ms="$2"
  local -n output_ref="$3"
  local -a content_lines=()
  local -a content_masks=()
  local -a work_lines=()
  local -a work_masks=()
  local -a styled_lines=()
  local -a frame_lines=()
  local text_width="${TOAST_TEXT_WIDTH[$toast_id]}"
  local text_height="${TOAST_TEXT_HEIGHT[$toast_id]}"
  local frame_step="${TOAST_FRAME_STEP[$toast_id]}"
  local step_count="${TOAST_STEP_COUNT[$toast_id]}"
  local delay_ms="${TOAST_DELAY_MS[$toast_id]}"
  local hold_ms="${TOAST_DURATION_MS[$toast_id]}"
  local enter_ms=$(( step_count * delay_ms ))
  local hold_end_ms=$(( enter_ms + hold_ms ))
  local offset=0
  local shift_left=0
  local visible_width
  local row
  local line
  local mask_line
  local frame_width
  local frame_height

  load_named_array "toast_${toast_id}_content_lines" content_lines
  load_named_array "toast_${toast_id}_content_masks" content_masks

  if (( delay_ms <= 0 )); then
    if (( elapsed_ms < hold_end_ms )); then
      offset=0
      shift_left=0
    else
      shift_left="$text_width"
    fi
  elif (( elapsed_ms < enter_ms )); then
    offset=$(( text_width - ((elapsed_ms / delay_ms) * frame_step) ))
    if (( offset < 0 )); then
      offset=0
    fi
  elif (( elapsed_ms < hold_end_ms )); then
    offset=0
  else
    shift_left=$(( ((elapsed_ms - hold_end_ms) / delay_ms) * frame_step ))
    if (( shift_left > text_width )); then
      shift_left="$text_width"
    fi
  fi

  if (( elapsed_ms < hold_end_ms )); then
    for (( row = 0; row < text_height; row += 1 )); do
      if (( offset >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
        work_masks+=("$(repeat_char "$text_width" "0")")
      else
        visible_width=$((text_width - offset))
        line="$(repeat_char "$offset" " ")${content_lines[row]:0:visible_width}"
        mask_line="$(repeat_char "$offset" "0")${content_masks[row]:0:visible_width}"
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
  else
    for (( row = 0; row < text_height; row += 1 )); do
      if (( shift_left >= text_width )); then
        work_lines+=("$(repeat_char "$text_width" " ")")
        work_masks+=("$(repeat_char "$text_width" "0")")
      else
        line="${content_lines[row]:shift_left:text_width}"
        mask_line="${content_masks[row]:shift_left:text_width}"
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
  fi

  build_styled_lines_for_toast "$toast_id" work_lines work_masks styled_lines
  build_frame_lines_for_style "$text_width" "$text_height" "${TOAST_STYLE_MODE[$toast_id]}" "${TOAST_PREFIX[$toast_id]}" "${TOAST_RESET[$toast_id]}" styled_lines frame_lines frame_width frame_height
  output_ref=("${frame_lines[@]}")
}

load_full_frame() {
  local toast_id="$1"
  local -n output_ref="$2"
  local -n lines_ref="toast_${toast_id}_full_frame_lines"
  output_ref=("${lines_ref[@]}")
}

build_toast_frame_for_now() {
  local toast_id="$1"
  local current_ms="$2"
  local -n output_ref="$3"
  local elapsed_ms=$((current_ms - TOAST_CREATED_MS[$toast_id]))
  local mode="${TOAST_MODE[$toast_id]}"
  local char_delay="${TOAST_DELAY_MS[$toast_id]}"
  local char_count="${TOAST_CHAR_COUNT[$toast_id]-0}"
  local step_count="${TOAST_STEP_COUNT[$toast_id]-0}"
  local enter_ms=0
  local hold_end_ms=0

  case "$mode" in
    none)
      load_full_frame "$toast_id" output_ref
      ;;
    typewriter)
      enter_ms=$((char_count * char_delay))
      hold_end_ms=$((enter_ms + TOAST_DURATION_MS[$toast_id]))
      if (( elapsed_ms >= enter_ms )) && (( elapsed_ms < hold_end_ms )); then
        load_full_frame "$toast_id" output_ref
      else
        build_typewriter_frame "$toast_id" "$elapsed_ms" output_ref
      fi
      ;;
    slide)
      enter_ms=$((step_count * char_delay))
      hold_end_ms=$((enter_ms + TOAST_DURATION_MS[$toast_id]))
      if (( elapsed_ms >= enter_ms )) && (( elapsed_ms < hold_end_ms )); then
        load_full_frame "$toast_id" output_ref
      else
        build_slide_frame "$toast_id" "$elapsed_ms" output_ref
      fi
      ;;
    *)
      load_full_frame "$toast_id" output_ref
      ;;
  esac
}

ingest_requests() {
  local request_file
  local current_ms
  local request_id
  local message_file
  local animation_mode
  local delay_ms
  local duration_ms
  local text_width
  local text_height
  local toast_style_mode
  local popup_style
  local margin_top
  local margin_right
  local created_ms
  local frame_height
  local next_y
  local toast_id
  local -a pending_files=()
  local existing_id

  for request_file in "$request_dir"/*.req; do
    if [[ -e "$request_file" ]]; then
      pending_files+=("$request_file")
    fi
  done

  if (( ${#pending_files[@]} == 0 )); then
    return
  fi

  refresh_client_geometry || return

  for request_file in "${pending_files[@]}"; do
    # shellcheck disable=SC1090
    source "$request_file"
    toast_id="$(sanitize_toast_id "$request_id")"

    if (( ${#active_toast_ids[@]} == 0 )); then
      renderer_margin_top="$margin_top"
      renderer_margin_right="$margin_right"
    fi

    next_y="$renderer_margin_top"
    for existing_id in "${active_toast_ids[@]}"; do
      next_y=$((next_y + TOAST_FRAME_HEIGHT[$existing_id] + TOAST_STACK_GAP))
    done

    frame_height="$text_height"
    if [[ "$toast_style_mode" == "normal" ]]; then
      frame_height=$((frame_height + 2))
    fi

    if (( next_y + frame_height > renderer_client_height )); then
      rm -f "$message_file" "$request_file"
      tmux display-message -t "$client_name" "tmux-toast: container full" >/dev/null 2>&1 || true
      continue
    fi

    load_request "$request_file"
  done
}

prune_expired_toasts() {
  local current_ms="$1"
  local toast_id
  local kept_ids=()

  for toast_id in "${active_toast_ids[@]}"; do
    if toast_is_expired "$toast_id" "$current_ms"; then
      remove_toast "$toast_id"
    else
      kept_ids+=("$toast_id")
    fi
  done

  active_toast_ids=("${kept_ids[@]}")
}

compose_current_rows() {
  local current_ms="$1"
  local toast_id
  local current_y
  local x
  local max_x
  local row
  local -a frame_lines=()

  clear_current_row_maps

  if (( ${#active_toast_ids[@]} == 0 )); then
    return
  fi

  refresh_client_geometry || return

  current_y="$renderer_margin_top"
  for toast_id in "${active_toast_ids[@]}"; do
    if (( current_y + TOAST_FRAME_HEIGHT[$toast_id] > renderer_client_height )); then
      break
    fi

    build_toast_frame_for_now "$toast_id" "$current_ms" frame_lines

    max_x=$((renderer_client_width - TOAST_FRAME_WIDTH[$toast_id]))
    if (( max_x < 0 )); then
      max_x=0
    fi
    x="$(clamp "$((max_x - renderer_margin_right))" 0 "$max_x")"

    for (( row = 0; row < ${#frame_lines[@]}; row += 1 )); do
      register_row_segment "$((current_y + row))" "$x" "${TOAST_FRAME_WIDTH[$toast_id]}" "${frame_lines[row]}"
    done

    current_y=$((current_y + TOAST_FRAME_HEIGHT[$toast_id] + TOAST_STACK_GAP))
  done
}

next_sleep_ms() {
  local current_ms="$1"
  local toast_id
  local due_ms
  local earliest_ms=-1
  local delta_ms

  if (( ${#active_toast_ids[@]} == 0 )); then
    printf '200'
    return
  fi

  for toast_id in "${active_toast_ids[@]}"; do
    due_ms="$(toast_next_due_ms "$toast_id")"
    if (( earliest_ms < 0 || due_ms < earliest_ms )); then
      earliest_ms="$due_ms"
    fi
  done

  delta_ms=$((earliest_ms - current_ms))
  if (( delta_ms < 0 )); then
    delta_ms=0
  fi

  printf '%s' "$delta_ms"
}

setup_write_lock

while :; do
  local_now_ms="$(now_ms)"

  ingest_requests
  prune_expired_toasts "$local_now_ms"
  compose_current_rows "$local_now_ms"
  render_changed_rows

  if (( ${#active_toast_ids[@]} == 0 )); then
    if (( idle_since_ms == 0 )); then
      idle_since_ms="$local_now_ms"
    elif (( local_now_ms - idle_since_ms >= IDLE_EXIT_MS )); then
      break
    fi
  else
    idle_since_ms=0
  fi

  sleep_ms="$(next_sleep_ms "$local_now_ms")"
  wake_requested=0
  if (( sleep_ms > 0 )); then
    sleep_milliseconds "$sleep_ms"
  fi
done
