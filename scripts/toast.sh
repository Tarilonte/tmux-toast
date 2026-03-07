#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PAD_X=2
DEFAULT_PAD_Y=1
DEFAULT_MARGIN_RIGHT=2
DEFAULT_MARGIN_TOP=1
DEFAULT_TOAST_STYLE_MODE='invert'
DEFAULT_TYPE_DELAY='0.06'
DEFAULT_ANIMATION_MODE='typewriter'
DEFAULT_TOAST_DURATION='5'
TOAST_STACK_GAP=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/options.sh
source "$SCRIPT_DIR/lib/options.sh"
# shellcheck source=./lib/input.sh
source "$SCRIPT_DIR/lib/input.sh"
# shellcheck source=./lib/format.sh
source "$SCRIPT_DIR/lib/format.sh"
# shellcheck source=./lib/layout.sh
source "$SCRIPT_DIR/lib/layout.sh"
# shellcheck source=./lib/style.sh
source "$SCRIPT_DIR/lib/style.sh"

display_error() {
  tmux display-message "tmux-toast: $1"
}

read_style_option() {
  local option_name="$1"
  tmux show-options -gv "$option_name" 2>/dev/null || true
}

sanitize_client_key() {
  local raw_value="$1"
  local safe_value

  safe_value="${raw_value//[^a-zA-Z0-9._-]/_}"
  if [[ -z "$safe_value" ]]; then
    safe_value="default"
  fi

  printf '%s' "$safe_value"
}

setup_toast_container() {
  local safe_client
  local container_root

  safe_client="$(sanitize_client_key "$toast_client_name")"
  container_root="${TMPDIR:-/tmp}/tmux-toast-container-${safe_client}"

  toast_container_entries_dir="${container_root}/entries"
  toast_container_lock_file="${container_root}/lock"

  mkdir -p "$toast_container_entries_dir"
  exec 8>"$toast_container_lock_file"
  toast_container_lock_open=1
}

prune_container_entries_locked() {
  local entry_file
  local entry_pid
  local entry_y
  local entry_height

  for entry_file in "$toast_container_entries_dir"/*.slot; do
    if [[ ! -e "$entry_file" ]]; then
      break
    fi

    entry_pid=""
    entry_y=""
    entry_height=""
    if ! IFS=' ' read -r entry_pid entry_y entry_height < "$entry_file"; then
      rm -f "$entry_file"
      continue
    fi

    if ! [[ "$entry_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$entry_pid" 2>/dev/null; then
      rm -f "$entry_file"
    fi
  done
}

release_container_slot() {
  if (( toast_container_lock_open == 0 )); then
    return
  fi

  flock -x 8 || true

  if (( toast_container_slot_registered == 1 )) && [[ -n "$toast_container_slot_file" ]]; then
    rm -f "$toast_container_slot_file" || true
  fi

  prune_container_entries_locked || true
  flock -u 8 || true

  exec 8>&- || true
  toast_container_lock_open=0
  toast_container_slot_registered=0
  toast_container_slot_file=""
}

reserve_container_slot() {
  local entry_file
  local entry_pid
  local entry_y
  local entry_height
  local next_y
  local entry_bottom

  if (( toast_container_lock_open == 0 )); then
    return 1
  fi

  next_y="$popup_y"

  flock -x 8
  prune_container_entries_locked

  for entry_file in "$toast_container_entries_dir"/*.slot; do
    if [[ ! -e "$entry_file" ]]; then
      break
    fi

    entry_pid=""
    entry_y=""
    entry_height=""
    if ! IFS=' ' read -r entry_pid entry_y entry_height < "$entry_file"; then
      rm -f "$entry_file"
      continue
    fi

    if ! [[ "$entry_pid" =~ ^[0-9]+$ ]] || ! [[ "$entry_y" =~ ^[0-9]+$ ]] || ! [[ "$entry_height" =~ ^[0-9]+$ ]]; then
      rm -f "$entry_file"
      continue
    fi

    if ! kill -0 "$entry_pid" 2>/dev/null; then
      rm -f "$entry_file"
      continue
    fi

    entry_bottom=$((entry_y + entry_height + TOAST_STACK_GAP))
    if (( entry_bottom > next_y )); then
      next_y="$entry_bottom"
    fi
  done

  if (( next_y > toast_max_y )); then
    flock -u 8
    return 1
  fi

  popup_y="$next_y"
  toast_container_slot_file="$toast_container_entries_dir/$$.slot"
  printf '%s %s %s\n' "$$" "$popup_y" "$popup_height" > "$toast_container_slot_file"
  toast_container_slot_registered=1

  flock -u 8
}

render_popup_from_decoded() {
  local decoded_text="$1"
  local -a source_lines
  local -a parsed_plain_lines
  local -a parsed_masks_lines
  local -a wrapped_plain_lines
  local -a wrapped_masks_lines
  local -a visible_plain_lines
  local -a visible_masks_lines
  local -a rendered_lines

  local longest_line=0
  local line
  local line_length
  local parsed_plain
  local parsed_masks
  local natural_popup_width
  local content_width
  local border_cols
  local border_rows
  local max_pad_x
  local effective_pad_x
  local inner_text_width
  local wrapped_line_count
  local natural_popup_height
  local content_height
  local max_x
  local max_y
  local max_pad_y
  local effective_pad_y
  local inner_text_height
  local visible_line_count
  local truncated=0
  local last_index
  local last_plain_line
  local last_masks_line
  local max_last_width
  local ellipsis_mask
  local content_blank_line
  local left_padding
  local right_padding
  local line_plain
  local line_masks
  local styled_line
  local trailing_spaces_count
  local trailing_spaces
  local i

  split_lines "$decoded_text" source_lines

  parsed_plain_lines=()
  parsed_masks_lines=()
  for line in "${source_lines[@]}"; do
    parsed_plain=""
    parsed_masks=""
    parse_markdown_line "$line" parsed_plain parsed_masks
    parsed_plain_lines+=("$parsed_plain")
    parsed_masks_lines+=("$parsed_masks")

    line_length="${#parsed_plain}"
    if (( line_length > longest_line )); then
      longest_line="$line_length"
    fi
  done

  if [[ "$toast_style_mode" == "normal" ]]; then
    border_cols=2
    border_rows=2
  else
    border_cols=0
    border_rows=0
  fi

  if [[ "$size_mode" == "auto" ]]; then
    natural_popup_width=$((longest_line + (2 * pad_x) + border_cols))
  else
    case "$size_mode" in
      small)
        natural_popup_width=$(((client_width * 45) / 100))
        ;;
      medium)
        natural_popup_width=$(((client_width * 65) / 100))
        ;;
      large)
        natural_popup_width=$(((client_width * 85) / 100))
        ;;
    esac
  fi

  popup_width="$(clamp "$natural_popup_width" 3 "$client_width")"
  content_width=$((popup_width - border_cols))
  if (( content_width < 1 )); then
    content_width=1
  fi

  max_pad_x=$(((content_width - 1) / 2))
  effective_pad_x="$pad_x"
  if (( effective_pad_x > max_pad_x )); then
    effective_pad_x="$max_pad_x"
  fi

  inner_text_width=$((content_width - (2 * effective_pad_x)))
  if (( inner_text_width < 1 )); then
    inner_text_width=1
  fi

  wrapped_plain_lines=()
  wrapped_masks_lines=()
  for (( i = 0; i < ${#parsed_plain_lines[@]}; i += 1 )); do
    wrap_parsed_line "$inner_text_width" "${parsed_plain_lines[i]}" "${parsed_masks_lines[i]}" wrapped_plain_lines wrapped_masks_lines
  done

  wrapped_line_count="${#wrapped_plain_lines[@]}"

  if [[ "$size_mode" == "auto" ]]; then
    natural_popup_height=$((wrapped_line_count + (2 * pad_y) + border_rows))
  else
    case "$size_mode" in
      small)
        natural_popup_height=$(((client_height * 30) / 100))
        ;;
      medium)
        natural_popup_height=$(((client_height * 50) / 100))
        ;;
      large)
        natural_popup_height=$(((client_height * 70) / 100))
        ;;
    esac
  fi

  popup_height="$(clamp "$natural_popup_height" 3 "$client_height")"
  content_height=$((popup_height - border_rows))
  if (( content_height < 1 )); then
    content_height=1
  fi

  max_x=$((client_width - popup_width))
  if (( max_x < 0 )); then
    max_x=0
  fi

  max_y=$((client_height - popup_height))
  if (( max_y < 0 )); then
    max_y=0
  fi

  popup_x="$(clamp "$((max_x - margin_right))" 0 "$max_x")"
  popup_y="$(clamp "$margin_top" 0 "$max_y")"
  toast_max_y="$max_y"

  max_pad_y=$(((content_height - 1) / 2))
  effective_pad_y="$pad_y"
  if (( effective_pad_y > max_pad_y )); then
    effective_pad_y="$max_pad_y"
  fi

  inner_text_height=$((content_height - (2 * effective_pad_y)))
  if (( inner_text_height < 1 )); then
    inner_text_height=1
  fi

  visible_line_count="$wrapped_line_count"
  if (( visible_line_count > inner_text_height )); then
    visible_line_count="$inner_text_height"
    truncated=1
  fi

  visible_plain_lines=()
  visible_masks_lines=()
  for (( i = 0; i < visible_line_count; i += 1 )); do
    visible_plain_lines+=("${wrapped_plain_lines[i]}")
    visible_masks_lines+=("${wrapped_masks_lines[i]}")
  done

  if (( truncated == 1 && visible_line_count > 0 )); then
    last_index=$((visible_line_count - 1))
    last_plain_line="${visible_plain_lines[last_index]}"
    last_masks_line="${visible_masks_lines[last_index]}"

    if (( inner_text_width >= 3 )); then
      max_last_width=$((inner_text_width - 3))
      if (( ${#last_plain_line} > max_last_width )); then
        last_plain_line="${last_plain_line:0:max_last_width}"
        last_masks_line="${last_masks_line:0:max_last_width}"
      fi

      if (( ${#last_masks_line} > 0 )); then
        ellipsis_mask="${last_masks_line:${#last_masks_line}-1:1}"
      else
        ellipsis_mask="0"
      fi

      visible_plain_lines[last_index]="${last_plain_line}..."
      visible_masks_lines[last_index]="${last_masks_line}${ellipsis_mask}${ellipsis_mask}${ellipsis_mask}"
    else
      visible_plain_lines[last_index]="${last_plain_line:0:inner_text_width}"
      visible_masks_lines[last_index]="${last_masks_line:0:inner_text_width}"
    fi
  fi

  content_blank_line="$(spaces "$content_width")"
  left_padding="$(spaces "$effective_pad_x")"
  right_padding="$left_padding"

  rendered_lines=()
  for (( i = 0; i < effective_pad_y; i += 1 )); do
    rendered_lines+=("$content_blank_line")
  done

  for (( i = 0; i < ${#visible_plain_lines[@]}; i += 1 )); do
    line_plain="${visible_plain_lines[i]}"
    line_masks="${visible_masks_lines[i]}"

    if (( ${#line_plain} > inner_text_width )); then
      line_plain="${line_plain:0:inner_text_width}"
      line_masks="${line_masks:0:inner_text_width}"
    fi

    styled_line="$(style_line "$line_plain" "$line_masks")"

    trailing_spaces_count=$((inner_text_width - ${#line_plain}))
    trailing_spaces="$(spaces "$trailing_spaces_count")"
    rendered_lines+=("${left_padding}${styled_line}${trailing_spaces}${right_padding}")
  done

  for (( i = 0; i < effective_pad_y; i += 1 )); do
    rendered_lines+=("$content_blank_line")
  done

  while (( ${#rendered_lines[@]} < content_height )); do
    rendered_lines+=("$content_blank_line")
  done

  if (( ${#rendered_lines[@]} > content_height )); then
    rendered_lines=("${rendered_lines[@]:0:content_height}")
  fi

  rendered_message=""
  for (( i = 0; i < ${#rendered_lines[@]}; i += 1 )); do
    rendered_message+="${rendered_lines[i]}"
    if (( i + 1 < ${#rendered_lines[@]} )); then
      rendered_message+=$'\n'
    fi
  done

  toast_render_width="$content_width"
  toast_render_height="$content_height"
}

show_tty_with_file() {
  local file_path="$1"

  "$tty_backend_script" "$file_path" "$type_delay" "$animation_mode" "$toast_render_width" "$toast_render_height" "$toast_duration" \
    "$toast_client_tty" "$popup_x" "$popup_y" "$toast_style_mode" "$popup_style" "$toast_client_name" "$client_width"
}

raw_message="${1-}"
if [[ -z "$raw_message" ]]; then
  display_error "message is required"
  exit 1
fi

pad_x="$(normalize_nonnegative_int "$(get_option "@tmux-toast-padding-x" "$DEFAULT_PAD_X")" "$DEFAULT_PAD_X")"
pad_y="$(normalize_nonnegative_int "$(get_option "@tmux-toast-padding-y" "$DEFAULT_PAD_Y")" "$DEFAULT_PAD_Y")"
margin_right="$(normalize_nonnegative_int "$(get_option "@tmux-toast-margin-right" "$DEFAULT_MARGIN_RIGHT")" "$DEFAULT_MARGIN_RIGHT")"
margin_top="$(normalize_nonnegative_int "$(get_option "@tmux-toast-margin-top" "$DEFAULT_MARGIN_TOP")" "$DEFAULT_MARGIN_TOP")"
size_mode="$(normalize_size_mode "$(get_option "@tmux-toast-size" "auto")")"
toast_style_mode="$(normalize_toast_style_mode "$(get_option "@tmux-toast-style" "$DEFAULT_TOAST_STYLE_MODE")")"
type_delay="$(normalize_nonnegative_number "$(get_option "@tmux-toast-type-delay" "$DEFAULT_TYPE_DELAY")" "$DEFAULT_TYPE_DELAY")"
toast_duration="$(normalize_nonnegative_number "$(get_option "@tmux-toast_duration" "$DEFAULT_TOAST_DURATION")" "$DEFAULT_TOAST_DURATION")"
animation_mode="$(normalize_animation_mode "$(get_option "@tmux-toast-animation-mode" "$DEFAULT_ANIMATION_MODE")")"

base_popup_style="$(read_style_option popup-style)"
if [[ -z "$base_popup_style" || "$base_popup_style" == "default" ]]; then
  base_popup_style="$(read_style_option window-active-style)"
fi

if [[ -z "$base_popup_style" || "$base_popup_style" == "default" ]]; then
  base_popup_style="$(read_style_option window-style)"
fi

if [[ -z "$base_popup_style" || "$base_popup_style" == "default" ]]; then
  base_popup_style="$(read_style_option status-style)"
fi

if [[ "$toast_style_mode" == "invert" ]]; then
  popup_style="$(invert_style_fg_bg "$base_popup_style")"
else
  popup_style="$base_popup_style"
fi

client_width="$(tmux display-message -p '#{client_width}')"
client_height="$(tmux display-message -p '#{client_height}')"
if ! [[ "$client_width" =~ ^[0-9]+$ ]] || ! [[ "$client_height" =~ ^[0-9]+$ ]]; then
  display_error "unable to read client size"
  exit 1
fi

toast_client_tty="$(tmux display-message -p '#{client_tty}')"
toast_client_name="$(tmux display-message -p '#{client_name}')"

if [[ -z "$toast_client_tty" || -z "$toast_client_name" ]]; then
  display_error "tty rendering requires an active tmux client"
  exit 1
fi

if [[ ! -w "$toast_client_tty" ]]; then
  display_error "client tty is not writable: $toast_client_tty"
  exit 1
fi

decoded_message="$(decode_message "$raw_message")"
render_popup_from_decoded "$decoded_message"

temp_file="$(mktemp "${TMPDIR:-/tmp}/tmux-toast.XXXXXX")"
printf '%s' "$rendered_message" > "$temp_file"

tty_backend_script="$SCRIPT_DIR/lib/backend_tty.sh"

toast_container_lock_open=0
toast_container_slot_registered=0
toast_container_slot_file=""
toast_container_entries_dir=""
toast_container_lock_file=""

setup_toast_container
trap release_container_slot EXIT INT TERM

if ! reserve_container_slot; then
  rm -f "$temp_file"
  display_error "toast container is full"
  exit 1
fi

if ! show_tty_with_file "$temp_file"; then
  rm -f "$temp_file"
  display_error "failed to render tty toast"
  exit 1
fi
