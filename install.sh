#!/usr/bin/env bash

set -uo pipefail

default_release_download_url="https://github.com/phoenixweiss/Bumpster/releases/latest/download"
release_download_url="${BUMPSTER_RELEASE_DOWNLOAD_URL:-$default_release_download_url}"
requested_home="${BUMPSTER_HOME:-$HOME/.bumpster}"
target_parent=""
target_name=""
target_home=""
temporary_root=""
staged_runtime=""
backup_dir=""
previous_runtime=""
previous_moved=false
new_runtime_moved=false
installation_complete=false
create_bump_wrapper=false
sha256_command=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Installation failed: %s\n' "$*" >&2
  return 1
}

remove_temporary_root() {
  local temporary_name

  if [[ -z "$temporary_root" || ! -e "$temporary_root" ]]; then
    return
  fi
  if [[ "$(dirname "$temporary_root")" != "$target_parent" ]]; then
    printf 'Refusing to remove unexpected temporary path: %s\n' \
      "$temporary_root" >&2
    return
  fi

  temporary_name="$(basename "$temporary_root")"
  case "$temporary_name" in
    ".$target_name.install."*)
      rm -rf -- "$temporary_root"
      ;;
    *)
      printf 'Refusing to remove unexpected temporary path: %s\n' \
        "$temporary_root" >&2
      ;;
  esac
}

rollback_installation() {
  local failed_runtime=""

  if [[ "$installation_complete" == "true" ]]; then
    return
  fi

  if [[ "$new_runtime_moved" == "true" && -e "$target_home" ]]; then
    failed_runtime="$temporary_root/failed-runtime"
    if ! mv "$target_home" "$failed_runtime"; then
      printf 'Could not move the failed runtime away from %s.\n' \
        "$target_home" >&2
      return
    fi
    new_runtime_moved=false
  fi

  if [[ "$previous_moved" == "true" && -d "$previous_runtime" ]]; then
    if mv "$previous_runtime" "$target_home"; then
      previous_moved=false
      rmdir "$backup_dir" 2>/dev/null || true
      backup_dir=""
      printf 'Previous Bumpster installation restored.\n' >&2
    else
      printf 'Automatic rollback failed. Previous installation remains at %s.\n' \
        "$previous_runtime" >&2
    fi
  fi
}

cleanup() {
  rollback_installation
  if [[ "$installation_complete" != "true" &&
    -n "$backup_dir" && -d "$backup_dir" ]]; then
    rmdir "$backup_dir" 2>/dev/null || true
  fi
  remove_temporary_root
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_commands() {
  local command_name

  for command_name in \
    awk basename chmod cp curl dirname mktemp mkdir mv rm rmdir tar; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      fail "$command_name is required."
      return 1
    fi
  done

  if command -v shasum >/dev/null 2>&1; then
    sha256_command="shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256_command="sha256sum"
  else
    fail "shasum or sha256sum is required."
    return 1
  fi
}

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

resolve_target_home() {
  local requested_parent
  local physical_home

  if [[ -z "$requested_home" || "$requested_home" != /* ]]; then
    fail "BUMPSTER_HOME must be an absolute path."
    return 1
  fi

  target_name="$(basename "$requested_home")"
  if [[ -z "$target_name" || "$target_name" == "." || "$target_name" == ".." ]]; then
    fail "BUMPSTER_HOME has an unsafe final path component."
    return 1
  fi

  requested_parent="$(dirname "$requested_home")"
  if ! mkdir -p "$requested_parent"; then
    fail "Could not create the parent directory for BUMPSTER_HOME."
    return 1
  fi
  if ! target_parent="$(cd "$requested_parent" && pwd -P)"; then
    fail "Could not resolve the parent directory for BUMPSTER_HOME."
    return 1
  fi
  target_home="$target_parent/$target_name"

  if ! physical_home="$(cd "$HOME" && pwd -P)"; then
    fail "Could not resolve HOME."
    return 1
  fi
  if [[ "$target_home" == "/" || "$target_home" == "$physical_home" ]]; then
    fail "Refusing to use a broad directory as BUMPSTER_HOME."
    return 1
  fi
  if [[ -L "$target_home" ]]; then
    fail "BUMPSTER_HOME must not be a symbolic link."
    return 1
  fi
  if [[ -e "$target_home" && ! -d "$target_home" ]]; then
    fail "BUMPSTER_HOME exists and is not a directory."
    return 1
  fi
}

configure_release_transport() {
  case "$release_download_url" in
    https://*)
      return 0
      ;;
    file://*)
      if [[ "${BUMPSTER_TEST_ALLOW_FILE_RELEASES:-false}" == "true" ]]; then
        return 0
      fi
      ;;
  esac

  fail "Release downloads must use HTTPS."
}

download_file() {
  local url="$1"
  local output_path="$2"
  local protocol="=https"

  if [[ "$url" == file://* ]]; then
    protocol="=file"
  fi

  curl \
    --disable \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto "$protocol" \
    --output "$output_path" \
    "$url"
}

parse_release_checksum() {
  local checksum_path="$1"
  local checksum_line

  checksum_line="$(<"$checksum_path")" || return 1
  if [[ ! "$checksum_line" =~ ^([0-9a-f]{64})[[:space:]][[:space:]](bumpster-((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))\.tar\.gz)$ ]]; then
    fail "SHA256SUMS does not contain one valid Bumpster runtime asset."
    return 1
  fi

  release_checksum="${BASH_REMATCH[1]}"
  archive_name="${BASH_REMATCH[2]}"
  release_version="${BASH_REMATCH[3]}"
}

version_is_greater() {
  local candidate="$1"
  local reference="$2"
  local candidate_major candidate_minor candidate_patch
  local reference_major reference_minor reference_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
  IFS=. read -r reference_major reference_minor reference_patch <<< "$reference"

  if ((candidate_major != reference_major)); then
    ((candidate_major > reference_major))
    return
  fi
  if ((candidate_minor != reference_minor)); then
    ((candidate_minor > reference_minor))
    return
  fi
  ((candidate_patch > reference_patch))
}

verify_release_archive() {
  local archive_path="$1"
  local actual_checksum
  local expected_entries
  local actual_entries
  local runtime_file
  local runtime_version_output

  actual_checksum="$(calculate_sha256 "$archive_path")" ||
    return 1
  if [[ "$actual_checksum" != "$release_checksum" ]]; then
    fail "Runtime archive checksum mismatch."
    return 1
  fi

  expected_entries="$(
    printf '%s\n' \
      "bumpster-$release_version/" \
      "bumpster-$release_version/LICENSE" \
      "bumpster-$release_version/VERSION" \
      "bumpster-$release_version/bumpster.sh" \
      "bumpster-$release_version/config.sh" \
      "bumpster-$release_version/lib/" \
      "bumpster-$release_version/lib/BUMPSTER_LOGO.ASCII" \
      "bumpster-$release_version/lib/functions.sh"
  )"
  actual_entries="$(tar -tzf "$archive_path")" || {
    fail "Could not read the runtime archive."
    return 1
  }
  if [[ "$actual_entries" != "$expected_entries" ]]; then
    fail "Runtime archive contents do not match the whitelist."
    return 1
  fi

  if ! tar -xzf "$archive_path" -C "$temporary_root"; then
    fail "Could not extract the runtime archive."
    return 1
  fi
  staged_runtime="$temporary_root/bumpster-$release_version"

  if [[ ! -d "$staged_runtime" || -L "$staged_runtime" ||
    ! -d "$staged_runtime/lib" || -L "$staged_runtime/lib" ]]; then
    fail "Runtime archive directory structure is unsafe."
    return 1
  fi
  for runtime_file in \
    LICENSE VERSION bumpster.sh config.sh \
    lib/BUMPSTER_LOGO.ASCII lib/functions.sh; do
    if [[ ! -f "$staged_runtime/$runtime_file" ||
      -L "$staged_runtime/$runtime_file" ]]; then
      fail "Runtime archive contains an unsafe file: $runtime_file"
      return 1
    fi
  done
  if [[ "$(<"$staged_runtime/VERSION")" != "$release_version" ]]; then
    fail "Runtime VERSION does not match the Release asset."
    return 1
  fi

  runtime_version_output="$(
    HOME="$HOME" \
      BUMPSTER_HOME="$staged_runtime" \
      bash "$staged_runtime/bumpster.sh" --version
  )" || {
    fail "Packaged Bumpster failed its version smoke test."
    return 1
  }
  if [[ "$runtime_version_output" != "Bumpster version: $release_version" ]]; then
    fail "Packaged Bumpster reported an unexpected version."
    return 1
  fi
}

preserve_user_data() {
  if [[ ! -e "$target_home/hooks" ]]; then
    return
  fi
  if [[ ! -d "$target_home/hooks" ]]; then
    fail "Existing hooks path is not a directory."
    return 1
  fi

  if ! cp -R "$target_home/hooks" "$staged_runtime/hooks"; then
    fail "Could not preserve user hooks."
    return 1
  fi
}

write_wrapper() {
  local wrapper_path="$1"
  local temporary_wrapper

  temporary_wrapper="$(mktemp "$target_home/bin/.wrapper.XXXXXX")" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'BUMPSTER_HOME=%q\n' "$target_home"
    printf 'export BUMPSTER_HOME\n'
    # The generated wrapper must contain the literal runtime variable references.
    # shellcheck disable=SC2016
    printf 'exec "$BUMPSTER_HOME/bumpster.sh" "$@"\n'
  } > "$temporary_wrapper" || return 1
  chmod +x "$temporary_wrapper" || return 1
  mv "$temporary_wrapper" "$wrapper_path"
}

create_wrappers() {
  if ! chmod +x "$target_home/bumpster.sh"; then
    fail "Could not make bumpster.sh executable."
    return 1
  fi
  if ! mkdir -p "$target_home/bin"; then
    fail "Could not create the command directory."
    return 1
  fi
  if ! write_wrapper "$target_home/bin/bumpster"; then
    fail "Could not create the bumpster wrapper."
    return 1
  fi
  if [[ "$create_bump_wrapper" == "true" ]] &&
    ! write_wrapper "$target_home/bin/bump"; then
    fail "Could not create the bump wrapper."
    return 1
  fi
}

select_bump_wrapper_behavior() {
  local existing_bump=""
  local existing_bump_parent=""
  local physical_existing_bump=""

  existing_bump="$(command -v bump 2>/dev/null || true)"
  if [[ "$existing_bump" == /* ]]; then
    existing_bump_parent="$(dirname "$existing_bump")"
    if physical_existing_bump="$(
      cd "$existing_bump_parent" 2>/dev/null &&
        printf '%s/%s' "$(pwd -P)" "$(basename "$existing_bump")"
    )"; then
      existing_bump="$physical_existing_bump"
    fi
  fi

  if [[ -z "$existing_bump" ||
    "$existing_bump" == "$target_home/bin/bump" ]]; then
    create_bump_wrapper=true
  else
    create_bump_wrapper=false
    log "The command 'bump' is already in use; its wrapper will not be changed."
  fi
}

install_release() {
  local checksum_path
  local archive_path
  local local_version=""
  local backup_version="unknown"

  temporary_root="$(
    mktemp -d "$target_parent/.$target_name.install.XXXXXX"
  )" || {
    fail "Could not create a temporary installation directory."
    return 1
  }
  checksum_path="$temporary_root/SHA256SUMS"

  log "Downloading the latest stable Bumpster Release metadata..."
  if ! download_file \
    "${release_download_url%/}/SHA256SUMS" \
    "$checksum_path"; then
    fail "Could not download SHA256SUMS."
    return 1
  fi
  parse_release_checksum "$checksum_path" || return 1
  archive_path="$temporary_root/$archive_name"

  if [[ -f "$target_home/VERSION" ]]; then
    local_version="$(<"$target_home/VERSION")"
    if [[ "$local_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
      backup_version="$local_version"
      if version_is_greater "$local_version" "$release_version"; then
        fail "Refusing to downgrade from $local_version to $release_version."
        return 1
      fi
    fi
  fi

  log "Downloading Bumpster $release_version..."
  if ! download_file \
    "${release_download_url%/}/$archive_name" \
    "$archive_path"; then
    fail "Could not download $archive_name."
    return 1
  fi
  verify_release_archive "$archive_path" || return 1
  preserve_user_data || return 1
  select_bump_wrapper_behavior

  if [[ -d "$target_home" ]]; then
    backup_dir="$(
      mktemp -d "$target_parent/$target_name.backup.$backup_version.XXXXXX"
    )" || {
      fail "Could not create a backup directory."
      return 1
    }
    previous_runtime="$backup_dir/runtime"
    previous_moved=true
    if ! mv "$target_home" "$previous_runtime"; then
      previous_moved=false
      fail "Could not move the existing installation to $previous_runtime."
      return 1
    fi
  fi

  new_runtime_moved=true
  if ! mv "$staged_runtime" "$target_home"; then
    new_runtime_moved=false
    fail "Could not activate the verified runtime."
    return 1
  fi

  create_wrappers || return 1
  installation_complete=true

  log "Bumpster $release_version installed in $target_home/bin."
  if [[ -n "$backup_dir" ]]; then
    log "Previous installation backup: $previous_runtime"
  fi
}

main() {
  require_commands || return 1
  resolve_target_home || return 1
  configure_release_transport || return 1
  install_release
}

main "$@"
