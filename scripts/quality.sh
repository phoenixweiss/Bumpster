#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version_file="$project_root/.shellcheck-version"
shell_files=()
syntax_only=false

if [[ "$#" -gt 1 ]]; then
  printf 'Usage: %s [--syntax-only]\n' "${0##*/}" >&2
  exit 2
fi

case "${1:-}" in
  "")
    ;;
  --syntax-only)
    syntax_only=true
    ;;
  *)
    printf 'Usage: %s [--syntax-only]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

while IFS= read -r shell_file; do
  shell_files+=("$shell_file")
done < <(
  find "$project_root" \
    -path "$project_root/.git" -prune -o \
    -path '*/node_modules' -prune -o \
    -path '*/dist' -prune -o \
    -type f -name '*.sh' -print |
    LC_ALL=C sort
)

if [[ "${#shell_files[@]}" -eq 0 ]]; then
  printf 'No shell files found.\n' >&2
  exit 1
fi

printf 'Checking Bash syntax in %d files...\n' "${#shell_files[@]}"
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file" || exit 1
done

if [[ "$syntax_only" == "true" ]]; then
  printf 'Bash syntax checks passed.\n'
  exit 0
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'ShellCheck is required. Install the version listed in %s.\n' "$version_file" >&2
  exit 1
fi

required_shellcheck_version="$(tr -d '[:space:]' < "$version_file")"
actual_shellcheck_version="$(shellcheck --version | awk '/^version:/{print $2}')"

if [[ "$actual_shellcheck_version" != "$required_shellcheck_version" ]]; then
  printf 'ShellCheck %s is required, but %s is installed.\n' \
    "$required_shellcheck_version" "$actual_shellcheck_version" >&2
  exit 1
fi

printf 'Running ShellCheck %s...\n' "$required_shellcheck_version"
shellcheck -x "${shell_files[@]}" || exit 1

printf 'Shell quality checks passed.\n'
