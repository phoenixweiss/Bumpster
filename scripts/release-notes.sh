#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
changelog_file="$project_root/CHANGELOG.md"

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s MAJOR.MINOR.PATCH\n' "${0##*/}" >&2
  exit 2
fi

version="$1"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Invalid release version: %s\n' "$version" >&2
  exit 2
fi

if [[ ! -f "$changelog_file" ]]; then
  printf 'Changelog not found: %s\n' "$changelog_file" >&2
  exit 1
fi

if ! section="$(
  awk -v version="$version" '
    BEGIN {
      heading = "## [" version "]"
      found = 0
    }

    /^## / {
      if (found) {
        exit
      }

      if ($0 == heading || index($0, heading " - ") == 1) {
        found = 1
        next
      }
    }

    found && /^\[[^]]+\]:[[:space:]]+https?:\/\// {
      exit
    }

    found {
      lines[++line_count] = $0
    }

    END {
      if (!found) {
        exit 2
      }

      first_line = 1
      while (first_line <= line_count && lines[first_line] ~ /^[[:space:]]*$/) {
        first_line++
      }

      last_line = line_count
      while (last_line >= first_line && lines[last_line] ~ /^[[:space:]]*$/) {
        last_line--
      }

      for (line_number = first_line; line_number <= last_line; line_number++) {
        print lines[line_number]
      }
    }
  ' "$changelog_file"
)"; then
  printf 'No CHANGELOG section found for version %s.\n' "$version" >&2
  exit 1
fi

if [[ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]]; then
  printf 'CHANGELOG section for version %s is empty.\n' "$version" >&2
  exit 1
fi

printf '%s\n' "$section"
