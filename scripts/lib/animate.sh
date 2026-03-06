#!/usr/bin/env bash

set -euo pipefail

file_path="${1-}"
type_delay="${2-0.06}"

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 1
fi

cleanup() {
  rm -f "$file_path"
}

trap cleanup EXIT

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
