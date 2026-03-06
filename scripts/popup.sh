#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PAD_X=2
DEFAULT_PAD_Y=1
ESC_HINT='[ESC]'

display_error() {
  tmux display-message "tmux-popup: $1"
}

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

spaces() {
  local count="$1"

  if (( count <= 0 )); then
    return
  fi

  printf '%*s' "$count" ''
}

decode_message() {
  local input="$1"
  local output=""
  local i=0
  local length="${#input}"
  local current
  local next

  while (( i < length )); do
    current="${input:i:1}"

    if [[ "$current" == "\\" ]] && (( i + 1 < length )); then
      next="${input:i+1:1}"

      if [[ "$next" == "\\" ]] && (( i + 2 < length )) && [[ "${input:i+2:1}" == 'n' ]]; then
        output+='\n'
        (( i += 3 ))
        continue
      fi

      if [[ "$next" == 'n' ]]; then
        output+=$'\n'
        (( i += 2 ))
        continue
      fi
    fi

    output+="$current"
    (( i += 1 ))
  done

  printf '%s' "$output"
}

split_lines() {
  local text="$1"
  local -n output_ref="$2"

  output_ref=()

  if [[ -z "$text" ]]; then
    output_ref=("")
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    output_ref+=("$line")
  done < <(printf '%s' "$text")

  if [[ "$text" == *$'\n' ]]; then
    output_ref+=("")
  fi

  if (( ${#output_ref[@]} == 0 )); then
    output_ref=("")
  fi
}

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

wrap_parsed_line() {
  local width="$1"
  local plain="$2"
  local masks="$3"
  local -n output_plain_ref="$4"
  local -n output_masks_ref="$5"

  local line_length="${#plain}"
  local start=0
  local end
  local split_index
  local cursor

  if (( line_length == 0 )); then
    output_plain_ref+=("")
    output_masks_ref+=("")
    return
  fi

  while (( line_length - start > width )); do
    end=$((start + width))
    split_index=-1

    for (( cursor = end - 1; cursor >= start; cursor -= 1 )); do
      if [[ "${plain:cursor:1}" == ' ' ]]; then
        split_index="$cursor"
        break
      fi
    done

    if (( split_index > start )); then
      output_plain_ref+=("${plain:start:split_index-start}")
      output_masks_ref+=("${masks:start:split_index-start}")
      start=$((split_index + 1))
      while (( start < line_length )) && [[ "${plain:start:1}" == ' ' ]]; do
        (( start += 1 ))
      done
    else
      output_plain_ref+=("${plain:start:width}")
      output_masks_ref+=("${masks:start:width}")
      start=$((start + width))
    fi
  done

  output_plain_ref+=("${plain:start:line_length-start}")
  output_masks_ref+=("${masks:start:line_length-start}")
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

if ! tmux list-commands display-popup >/dev/null 2>&1; then
  display_error "display-popup is unavailable (tmux 3.2+ required)"
  exit 1
fi

raw_message="${1-}"
if [[ -z "$raw_message" ]]; then
  display_error "message is required"
  exit 1
fi

pad_x="$(get_option "@tmux-popup-padding-x" "$DEFAULT_PAD_X")"
pad_y="$(get_option "@tmux-popup-padding-y" "$DEFAULT_PAD_Y")"

if ! [[ "$pad_x" =~ ^[0-9]+$ ]]; then
  pad_x="$DEFAULT_PAD_X"
fi

if ! [[ "$pad_y" =~ ^[0-9]+$ ]]; then
  pad_y="$DEFAULT_PAD_Y"
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

natural_popup_width=$((longest_line + (2 * pad_x) + border_cols))
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
natural_popup_height=$((wrapped_line_count + (2 * pad_y) + border_rows))
popup_height="$(clamp "$natural_popup_height" 3 "$client_height")"
content_height=$((popup_height - border_rows))
if (( content_height < 1 )); then
  content_height=1
fi

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

if ! tmux display-popup "${popup_target[@]}" -d "$popup_directory" -w "$popup_width" -h "$popup_height" -T "$popup_title" \
  sh -c 'cat "$1"; rm -f "$1"' sh "$temp_file"; then
  rm -f "$temp_file"
  display_error "failed to open popup"
  exit 1
fi
