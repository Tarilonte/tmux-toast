#!/usr/bin/env bash

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
