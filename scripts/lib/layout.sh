#!/usr/bin/env bash

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
