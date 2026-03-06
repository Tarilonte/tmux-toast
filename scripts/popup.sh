#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PAD_X=2
DEFAULT_PAD_Y=1
DEFAULT_MARGIN_RIGHT=2
DEFAULT_MARGIN_TOP=1
DEFAULT_INVERT_COLORS='on'
ESC_HINT='[ESC]'

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
  tmux display-message "tmux-popup: $1"
}

if ! tmux list-commands display-popup >/dev/null 2>&1; then
  display_error "display-popup is unavailable (tmux 3.2+ required)"
  exit 1
fi

raw_message="${1-}"
if [[ -z "$raw_message" ]]; then
  display_error "message is required"
  exit 1
fi

pad_x="$(normalize_nonnegative_int "$(get_option "@tmux-popup-padding-x" "$DEFAULT_PAD_X")" "$DEFAULT_PAD_X")"
pad_y="$(normalize_nonnegative_int "$(get_option "@tmux-popup-padding-y" "$DEFAULT_PAD_Y")" "$DEFAULT_PAD_Y")"
margin_right="$(normalize_nonnegative_int "$(get_option "@tmux-popup-margin-right" "$DEFAULT_MARGIN_RIGHT")" "$DEFAULT_MARGIN_RIGHT")"
margin_top="$(normalize_nonnegative_int "$(get_option "@tmux-popup-margin-top" "$DEFAULT_MARGIN_TOP")" "$DEFAULT_MARGIN_TOP")"
size_mode="$(normalize_size_mode "$(get_option "@tmux-popup-size" "auto")")"
invert_colors="$(normalize_on_off "$(get_option "@tmux-popup-invert-colors" "$DEFAULT_INVERT_COLORS")" "$DEFAULT_INVERT_COLORS")"

configured_popup_style="$(get_option "@tmux-popup-style" "")"
if [[ -n "$configured_popup_style" ]]; then
  base_popup_style="$configured_popup_style"
else
  base_popup_style="$(tmux display-message -p '#{E:popup-style}')"
fi

if [[ "$invert_colors" == "on" ]]; then
  popup_style="$(invert_style_fg_bg "$base_popup_style")"
else
  popup_style="$base_popup_style"
fi

decoded_message="$(decode_message "$raw_message")"
split_lines "$decoded_message" source_lines

parsed_plain_lines=()
parsed_masks_lines=()
longest_line=0
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

client_width="$(tmux display-message -p '#{client_width}')"
client_height="$(tmux display-message -p '#{client_height}')"

if ! [[ "$client_width" =~ ^[0-9]+$ ]] || ! [[ "$client_height" =~ ^[0-9]+$ ]]; then
  display_error "unable to read client size"
  exit 1
fi

border_cols=2
border_rows=2

if [[ "$size_mode" == "auto" ]]; then
  natural_popup_width=$((longest_line + (2 * pad_x) + border_cols))
else
  case "$size_mode" in
    small)
      preset_width_pct=45
      ;;
    medium)
      preset_width_pct=65
      ;;
    large)
      preset_width_pct=85
      ;;
  esac
  natural_popup_width=$(((client_width * preset_width_pct) / 100))
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
      preset_height_pct=30
      ;;
    medium)
      preset_height_pct=50
      ;;
    large)
      preset_height_pct=70
      ;;
  esac
  natural_popup_height=$(((client_height * preset_height_pct) / 100))
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
truncated=0
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

temp_file="$(mktemp "${TMPDIR:-/tmp}/tmux-popup.XXXXXX")"
printf '%s' "$rendered_message" > "$temp_file"

popup_title="#[align=right]${ESC_HINT}"

popup_directory="$(tmux display-message -p '#{pane_current_path}')"
popup_target=()
if [[ -n "${TMUX_PANE-}" ]]; then
  popup_target=(-t "$TMUX_PANE")
fi

if ! tmux display-popup "${popup_target[@]}" -d "$popup_directory" -x "$popup_x" -y "$popup_y" -w "$popup_width" -h "$popup_height" -s "$popup_style" -T "$popup_title" \
  sh -c 'cat "$1"; rm -f "$1"' sh "$temp_file"; then
  rm -f "$temp_file"
  display_error "failed to open popup"
  exit 1
fi
