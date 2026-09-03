#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="${BUMPSTER_REPOSITORY:-phoenixweiss/Bumpster}"
expected_release_tag="${EXPECTED_RELEASE_TAG:-}"
latest_download_url="https://github.com/$repository/releases/latest/download"
smoke_root=""
release_checksum=""
release_archive_name=""
release_version=""
sha256_command=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Release smoke failed: %s\n' "$*" >&2
  return 1
}

cleanup() {
  local smoke_name

  if [[ -z "$smoke_root" || ! -d "$smoke_root" ]]; then
    return
  fi

  smoke_name="$(basename "$smoke_root")"
  case "$smoke_name" in
    bumpster-release-smoke.*)
      rm -rf -- "$smoke_root"
      ;;
    *)
      printf 'Refusing to remove unexpected smoke path: %s\n' \
        "$smoke_root" >&2
      ;;
  esac
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_commands() {
  local command_name

  for command_name in \
    awk bash basename chmod cp curl dirname find gh git mktemp mkdir rm sed sort tar; do
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

download_file() {
  local url="$1"
  local output_path="$2"

  curl \
    --disable \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --output "$output_path" \
    "$url"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    fail "$message (expected: '$expected', actual: '$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message (missing: '$needle')"
  fi
}

parse_release_checksum() {
  local checksum_path="$1"
  local checksum_line

  checksum_line="$(<"$checksum_path")" || return 1
  if [[ ! "$checksum_line" =~ ^([0-9a-f]{64})[[:space:]][[:space:]](bumpster-((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))\.tar\.gz)$ ]]; then
    fail "SHA256SUMS does not describe one valid runtime asset."
    return 1
  fi

  release_checksum="${BASH_REMATCH[1]}"
  release_archive_name="${BASH_REMATCH[2]}"
  release_version="${BASH_REMATCH[3]}"
}

verify_public_release() {
  local latest_tag
  local checksum_path="$smoke_root/SHA256SUMS"
  local archive_path
  local actual_checksum
  local expected_contents
  local actual_contents

  latest_tag="$(
    gh api "repos/$repository/releases/latest" --jq '.tag_name'
  )" || {
    fail "Could not resolve the latest GitHub Release."
    return 1
  }
  if [[ ! "$latest_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    fail "The latest GitHub Release tag is not semantic: $latest_tag"
    return 1
  fi
  if [[ -n "$expected_release_tag" &&
    "$latest_tag" != "$expected_release_tag" ]]; then
    fail "Latest Release $latest_tag does not match $expected_release_tag."
    return 1
  fi

  download_file "$latest_download_url/SHA256SUMS" "$checksum_path" || {
    fail "Could not download the public SHA256SUMS asset."
    return 1
  }
  parse_release_checksum "$checksum_path" || return 1
  assert_equal "${latest_tag#v}" "$release_version" \
    "Release tag and runtime version differ" || return 1

  archive_path="$smoke_root/$release_archive_name"
  download_file "$latest_download_url/$release_archive_name" "$archive_path" || {
    fail "Could not download the public runtime archive."
    return 1
  }
  actual_checksum="$(calculate_sha256 "$archive_path")" || return 1
  assert_equal "$release_checksum" "$actual_checksum" \
    "Public runtime checksum differs from SHA256SUMS" || return 1

  expected_contents="$(
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
  actual_contents="$(tar -tzf "$archive_path")" || return 1
  assert_equal "$expected_contents" "$actual_contents" \
    "Public runtime archive contents differ from the whitelist" || return 1

  gh attestation verify "$archive_path" --repo "$repository" >/dev/null || {
    fail "GitHub artifact attestation verification failed."
    return 1
  }

  log "Verified public Release $latest_tag, checksum, contents, and attestation."
}

assert_minimal_installation() {
  local target_home="$1"
  local include_hook="${2:-false}"
  local expected_files
  local actual_files
  local expected_directories
  local actual_directories
  local symbolic_links

  expected_files="$({
    printf '%s\n' \
      LICENSE \
      VERSION \
      bin/bumpster \
      bumpster.sh \
      config.sh \
      lib/BUMPSTER_LOGO.ASCII \
      lib/functions.sh
    if [[ -f "$target_home/bin/bump" ]]; then
      printf '%s\n' bin/bump
    fi
    if [[ "$include_hook" == "true" ]]; then
      printf '%s\n' hooks/pre-bump
    fi
  } | LC_ALL=C sort)"
  actual_files="$(
    cd "$target_home" &&
      find . -type f -print |
      sed 's#^\./##' |
      LC_ALL=C sort
  )" || return 1
  assert_equal "$expected_files" "$actual_files" \
    "Installed runtime contains missing or unexpected files" || return 1

  expected_directories="$({
    printf '%s\n' . bin lib
    if [[ "$include_hook" == "true" ]]; then
      printf '%s\n' hooks
    fi
  } | LC_ALL=C sort)"
  actual_directories="$(
    cd "$target_home" &&
      find . -type d -print |
      sed 's#^\./##' |
      LC_ALL=C sort
  )" || return 1
  assert_equal "$expected_directories" "$actual_directories" \
    "Installed runtime contains unexpected directories" || return 1

  symbolic_links="$(
    find "$target_home" -type l -print
  )" || return 1
  assert_equal "" "$symbolic_links" \
    "Installed runtime contains symbolic links"
}

assert_no_temporary_directories() {
  local home_dir="$1"
  local temporary_directories

  temporary_directories="$(
    find "$home_dir" \
      -maxdepth 1 \
      -type d \
      \( -name '.*.install.*' -o -name '.*.update.*' \) \
      -print
  )" || return 1
  assert_equal "" "$temporary_directories" \
    "Install or update left temporary directories behind"
}

verify_installed_cli() {
  local home_dir="$1"
  local target_home="$2"
  local version_output
  local help_output

  version_output="$(
    HOME="$home_dir" \
      PATH="$target_home/bin:$PATH" \
      "$target_home/bin/bumpster" --version
  )" || return 1
  assert_equal "Bumpster version: $release_version" "$version_output" \
    "Installed CLI reports the wrong version" || return 1

  help_output="$(
    HOME="$home_dir" \
      PATH="$target_home/bin:$PATH" \
      "$target_home/bin/bumpster" --help
  )" || return 1
  assert_contains "$help_output" "Bumpster $release_version" \
    "Installed CLI help reports the wrong version" || return 1
  assert_contains "$help_output" "| X |.| Y |.| Z |  BUMPSTER" \
    "Installed CLI help is missing the uppercase Terminal identity" || return 1
  assert_contains "$help_output" \
    "+---+ +---+ +---+

Bumpster $release_version" \
    "Installed CLI help does not separate the Terminal identity"
}

run_installer() {
  local installer_path="$1"
  local home_dir="$2"
  local target_home="$3"

  HOME="$home_dir" \
    BUMPSTER_HOME="$target_home" \
    bash "$installer_path"
}

test_clean_install() {
  local test_root="$smoke_root/clean-install"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local installer_path="$smoke_root/install-main.sh"
  local update_output

  mkdir -p "$home_dir" || return 1
  download_file \
    "https://raw.githubusercontent.com/$repository/main/install.sh" \
    "$installer_path" || return 1
  bash -n "$installer_path" || return 1

  run_installer "$installer_path" "$home_dir" "$target_home" >/dev/null ||
    return 1
  verify_installed_cli "$home_dir" "$target_home" || return 1
  assert_minimal_installation "$target_home" || return 1

  update_output="$(
    HOME="$home_dir" \
      PATH="$target_home/bin:$PATH" \
      "$target_home/bin/bumpster" --update
  )" || return 1
  assert_contains "$update_output" \
    "already using the latest version ($release_version)" \
    "Latest Release self-update is not a clean no-op" || return 1
  assert_no_temporary_directories "$home_dir" || return 1

  log "Verified clean installation and no-op self-update."
}

create_legacy_installation() {
  local target_home="$1"

  mkdir -p "$target_home" || return 1
  git -C "$project_root" archive v0.8.0 |
    tar -xf - -C "$target_home" || return 1
  mkdir -p "$target_home/bin" "$target_home/hooks" || return 1
  printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$target_home/hooks/pre-bump" || return 1
  chmod +x "$target_home/hooks/pre-bump" || return 1

  {
    printf '#!/usr/bin/env bash\n'
    printf 'BUMPSTER_HOME=%q\n' "$target_home"
    printf 'export BUMPSTER_HOME\n'
    # The fixture wrapper must contain literal runtime variable references.
    # shellcheck disable=SC2016
    printf 'exec "$BUMPSTER_HOME/bumpster.sh" "$@"\n'
  } > "$target_home/bin/bumpster" || return 1
  cp "$target_home/bin/bumpster" "$target_home/bin/bump" || return 1
  chmod +x "$target_home/bin/bumpster" "$target_home/bin/bump"
}

test_legacy_migration() {
  local test_root="$smoke_root/legacy-migration"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local installer_path="$smoke_root/install-v0.9.0.sh"
  local backup_version_file

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1
  printf 'GIT_MASTER_BRANCH="stable"\n' > "$home_dir/.bumpsterrc" ||
    return 1

  download_file \
    "https://raw.githubusercontent.com/$repository/v0.9.0/install.sh" \
    "$installer_path" || return 1
  bash -n "$installer_path" || return 1
  run_installer "$installer_path" "$home_dir" "$target_home" >/dev/null ||
    return 1

  verify_installed_cli "$home_dir" "$target_home" || return 1
  assert_minimal_installation "$target_home" true || return 1
  assert_equal '#!/usr/bin/env bash
exit 0' "$(<"$target_home/hooks/pre-bump")" \
    "Migration did not preserve the user hook" || return 1
  assert_equal 'GIT_MASTER_BRANCH="stable"' "$(<"$home_dir/.bumpsterrc")" \
    "Migration changed the user configuration" || return 1

  backup_version_file="$(
    find "$home_dir" \
      -maxdepth 3 \
      -type f \
      -path '*/.bumpster.backup.0.8.0.*/runtime/VERSION' \
      -print
  )" || return 1
  if [[ -z "$backup_version_file" ||
    "$backup_version_file" == *$'\n'* ]]; then
    fail "Migration did not create exactly one identifiable 0.8.0 backup."
    return 1
  fi
  assert_equal "0.8.0" "$(<"$backup_version_file")" \
    "Migration backup contains the wrong version" || return 1
  assert_no_temporary_directories "$home_dir" || return 1

  log "Verified migration from v0.8.0 to the latest public Release."
}

main() {
  if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    fail "BUMPSTER_REPOSITORY must use the OWNER/REPOSITORY format."
    return 1
  fi

  require_commands || return 1
  smoke_root="$(
    mktemp -d "${TMPDIR:-/tmp}/bumpster-release-smoke.XXXXXX"
  )" || {
    fail "Could not create the release smoke directory."
    return 1
  }

  verify_public_release || return 1
  test_clean_install || return 1
  test_legacy_migration || return 1

  log "Public Bumpster $release_version smoke tests passed."
}

main "$@"
