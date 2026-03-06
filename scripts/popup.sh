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

wrap_lines() {
  local width="$1"
  local -n input_ref="$2"
  local -n output_ref="$3"

  output_ref=()

  for original_line in "${input_ref[@]}"; do
    local remaining="$original_line"

    if [[ -z "$remaining" ]]; then
      output_ref+=("")
      continue
    fi

    while (( ${#remaining} > width )); do
      local chunk="${remaining:0:width}"
      local split_index=-1
      local cursor

      for (( cursor = width - 1; cursor >= 0; cursor -= 1 )); do
        if [[ "${chunk:cursor:1}" == ' ' ]]; then
          split_index="$cursor"
          break
        fi
      done

      if (( split_index > 0 )); then
        output_ref+=("${remaining:0:split_index}")
        remaining="${remaining:split_index+1}"
        while [[ "$remaining" == ' '* ]]; do
          remaining="${remaining# }"
        done
      else
        output_ref+=("${remaining:0:width}")
        remaining="${remaining:width}"
      fi
    done

    output_ref+=("$remaining")
  done
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

longest_line=0
for line in "${source_lines[@]}"; do
  line_length="${#line}"
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

wrap_lines "$inner_text_width" source_lines wrapped_lines

wrapped_line_count="${#wrapped_lines[@]}"
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

visible_lines=()
for (( i = 0; i < visible_line_count; i += 1 )); do
  visible_lines+=("${wrapped_lines[i]}")
done

if (( truncated == 1 && visible_line_count > 0 )); then
  last_index=$((visible_line_count - 1))
  last_line="${visible_lines[last_index]}"
  if (( inner_text_width >= 3 )); then
    max_last_width=$((inner_text_width - 3))
    if (( ${#last_line} > max_last_width )); then
      last_line="${last_line:0:max_last_width}"
    fi
    visible_lines[last_index]="$last_line..."
  else
    visible_lines[last_index]="${last_line:0:inner_text_width}"
  fi
fi

content_blank_line="$(spaces "$content_width")"
left_padding="$(spaces "$effective_pad_x")"
right_padding="$left_padding"

rendered_lines=()
for (( i = 0; i < effective_pad_y; i += 1 )); do
  rendered_lines+=("$content_blank_line")
done

for line in "${visible_lines[@]}"; do
  if (( ${#line} > inner_text_width )); then
    line="${line:0:inner_text_width}"
  fi

  trailing_spaces_count=$((inner_text_width - ${#line}))
  trailing_spaces="$(spaces "$trailing_spaces_count")"
  rendered_lines+=("${left_padding}${line}${trailing_spaces}${right_padding}")
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
