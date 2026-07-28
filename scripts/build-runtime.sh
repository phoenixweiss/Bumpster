#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_argument="${1:-}"
source_ref="${2:-HEAD}"
runtime_files=(
  "LICENSE"
  "VERSION"
  "bumpster.sh"
  "config.sh"
  "lib/BUMPSTER_LOGO.ASCII"
  "lib/functions.sh"
)
output_dir=""
resolved_ref=""
version=""
archive_name=""
archive_path=""
checksum_path=""
temporary_archive=""
temporary_checksum=""
published_archive=false
sha256_command=""

cleanup() {
  if [[ -n "$temporary_archive" && -f "$temporary_archive" ]]; then
    rm -f -- "$temporary_archive"
  fi
  if [[ -n "$temporary_checksum" && -f "$temporary_checksum" ]]; then
    rm -f -- "$temporary_checksum"
  fi
  if [[ "$published_archive" == "true" && -n "$archive_path" && -f "$archive_path" ]]; then
    rm -f -- "$archive_path"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  printf 'Usage: %s OUTPUT_DIR [GIT_REF]\n' "${0##*/}" >&2
  exit 2
fi
if [[ -z "$output_argument" ]]; then
  printf 'Output directory must not be empty.\n' >&2
  exit 2
fi

for required_command in git gzip mktemp awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf '%s is required to build the runtime archive.\n' "$required_command" >&2
    exit 1
  fi
done
if command -v shasum >/dev/null 2>&1; then
  sha256_command="shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256_command="sha256sum"
else
  printf 'shasum or sha256sum is required to build the runtime archive.\n' >&2
  exit 1
fi

calculate_sha256() {
  local file_path="$1"

  case "$sha256_command" in
    shasum)
      shasum -a 256 "$file_path" | awk '{print $1}'
      ;;
    sha256sum)
      sha256sum "$file_path" | awk '{print $1}'
      ;;
    *)
      return 1
      ;;
  esac
}

if ! resolved_ref="$(git -C "$project_root" rev-parse --verify "$source_ref^{commit}" 2>/dev/null)"; then
  printf 'Git ref does not resolve to a commit: %s\n' "$source_ref" >&2
  exit 1
fi
if ! version="$(git -C "$project_root" show "$resolved_ref:VERSION" 2>/dev/null)"; then
  printf 'VERSION is missing from Git ref %s.\n' "$source_ref" >&2
  exit 1
fi
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'VERSION in Git ref %s is not MAJOR.MINOR.PATCH.\n' "$source_ref" >&2
  exit 1
fi

for runtime_file in "${runtime_files[@]}"; do
  if ! git -C "$project_root" cat-file -e "$resolved_ref:$runtime_file" 2>/dev/null; then
    printf 'Runtime file is missing from Git ref %s: %s\n' \
      "$source_ref" "$runtime_file" >&2
    exit 1
  fi
done

mkdir -p "$output_argument" || {
  printf 'Could not create output directory: %s\n' "$output_argument" >&2
  exit 1
}
if ! output_dir="$(cd "$output_argument" && pwd -P)"; then
  printf 'Could not resolve output directory: %s\n' "$output_argument" >&2
  exit 1
fi
if [[ "$output_dir" == "/" ]]; then
  printf 'Refusing to write runtime assets to the filesystem root.\n' >&2
  exit 1
fi

archive_name="bumpster-$version.tar.gz"
archive_path="$output_dir/$archive_name"
checksum_path="$output_dir/SHA256SUMS"
if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  printf 'Runtime output already exists in %s. Use an empty directory.\n' \
    "$output_dir" >&2
  exit 1
fi

temporary_archive="$(mktemp "$output_dir/.bumpster-runtime.XXXXXX")" || {
  printf 'Could not create a temporary runtime archive.\n' >&2
  exit 1
}
temporary_checksum="$(mktemp "$output_dir/.bumpster-checksum.XXXXXX")" || {
  printf 'Could not create a temporary checksum file.\n' >&2
  exit 1
}

if ! git -C "$project_root" archive \
  --format=tar \
  --prefix="bumpster-$version/" \
  "$resolved_ref" \
  -- "${runtime_files[@]}" |
  gzip -n -9 > "$temporary_archive"; then
  printf 'Failed to build runtime archive from Git ref %s.\n' "$source_ref" >&2
  exit 1
fi

archive_checksum="$(calculate_sha256 "$temporary_archive")" || {
  printf 'Failed to calculate the runtime archive checksum.\n' >&2
  exit 1
}
if [[ ! "$archive_checksum" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'Failed to calculate the runtime archive checksum.\n' >&2
  exit 1
fi
printf '%s  %s\n' "$archive_checksum" "$archive_name" > "$temporary_checksum" || {
  printf 'Failed to write the runtime checksum file.\n' >&2
  exit 1
}

mv "$temporary_archive" "$archive_path" || {
  printf 'Failed to publish runtime archive in %s.\n' "$output_dir" >&2
  exit 1
}
temporary_archive=""
published_archive=true
mv "$temporary_checksum" "$checksum_path" || {
  printf 'Failed to publish runtime checksum in %s.\n' "$output_dir" >&2
  exit 1
}
temporary_checksum=""
published_archive=false

printf 'Runtime archive: %s\n' "$archive_path"
printf 'Checksums: %s\n' "$checksum_path"
