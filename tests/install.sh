#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite_root=""
runtime_path="/usr/bin:/bin:/usr/sbin:/sbin"
passed=0
failed=0
sha256_command=""

cleanup() {
  if [[ "${KEEP_TEST_TMP:-false}" == "true" ]]; then
    printf 'Install test files kept at %s\n' "$suite_root"
    return
  fi

  if [[ -n "$suite_root" && "$suite_root" != "/" &&
    "$(basename "$suite_root")" == bumpster-install-tests.* ]]; then
    rm -rf -- "$suite_root"
  fi
}

trap cleanup EXIT INT TERM

fail() {
  printf '    %s\n' "$*" >&2
  return 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
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

add_command_directory_to_runtime_path() {
  local command_name="$1"
  local command_path
  local command_dir

  command_path="$(command -v "$command_name" 2>/dev/null)" ||
    fail "$command_name is required for install tests" || return 1
  command_dir="$(dirname "$command_path")" || return 1

  case ":$runtime_path:" in
    *":$command_dir:"*)
      ;;
    *)
      runtime_path="$command_dir:$runtime_path"
      ;;
  esac
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

create_release_fixture() {
  local fixture_name="$1"
  local version="$2"
  local extra_file="${3:-}"
  local fixture_root="$suite_root/$fixture_name"
  local source_dir="$fixture_root/source"
  local release_dir="$fixture_root/release"
  local archive_name="bumpster-$version.tar.gz"
  local checksum

  mkdir -p "$source_dir/lib" "$release_dir" || return 1
  cp \
    "$project_root/LICENSE" \
    "$project_root/bumpster.sh" \
    "$project_root/config.sh" \
    "$source_dir/" || return 1
  cp \
    "$project_root/lib/BUMPSTER_LOGO.ASCII" \
    "$project_root/lib/functions.sh" \
    "$source_dir/lib/" || return 1
  printf '%s' "$version" > "$source_dir/VERSION" || return 1

  git -C "$source_dir" init -q || return 1
  git -C "$source_dir" config user.name "Bumpster Install Tests" || return 1
  git -C "$source_dir" config user.email "install-tests@example.invalid" ||
    return 1
  git -C "$source_dir" add . || return 1
  git -C "$source_dir" commit -q -m "Create runtime fixture" || return 1

  if [[ -n "$extra_file" ]]; then
    printf 'unexpected\n' > "$source_dir/$extra_file" || return 1
    git -C "$source_dir" add "$extra_file" || return 1
    git -C "$source_dir" commit -q -m "Add unexpected runtime file" || return 1
  fi

  runtime_files=(
    LICENSE
    VERSION
    bumpster.sh
    config.sh
    lib/BUMPSTER_LOGO.ASCII
    lib/functions.sh
  )
  if [[ -n "$extra_file" ]]; then
    runtime_files+=("$extra_file")
  fi

  git -C "$source_dir" archive \
    --format=tar \
    --prefix="bumpster-$version/" \
    HEAD \
    -- "${runtime_files[@]}" |
    gzip -n -9 > "$release_dir/$archive_name" || return 1

  checksum="$(calculate_sha256 "$release_dir/$archive_name")" || return 1
  printf '%s  %s\n' "$checksum" "$archive_name" \
    > "$release_dir/SHA256SUMS" || return 1

  printf '%s\n' "$release_dir"
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

release_url_for_directory() {
  local release_dir="$1"
  local windows_path

  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      windows_path="$(cygpath -m "$release_dir")" || return 1
      printf 'file:///%s\n' "$windows_path"
      ;;
    *)
      printf 'file://%s\n' "$release_dir"
      ;;
  esac
}

run_installer() {
  local home_dir="$1"
  local target_home="$2"
  local release_dir="$3"
  local path_value="${4:-$runtime_path}"

  HOME="$home_dir" \
    BUMPSTER_HOME="$target_home" \
    BUMPSTER_RELEASE_DOWNLOAD_URL="$(release_url_for_directory "$release_dir")" \
    BUMPSTER_TEST_ALLOW_FILE_RELEASES=true \
    PATH="$path_value" \
    bash "$project_root/install.sh"
}

installed_version() {
  local home_dir="$1"
  local target_home="$2"

  HOME="$home_dir" \
    PATH="$target_home/bin:$runtime_path" \
    "$target_home/bin/bumpster" --version
}

assert_minimal_installation() {
  local target_home="$1"
  local include_hook="${2:-false}"
  local expected_files
  local actual_files

  expected_files="$({
    printf '%s\n' \
      LICENSE \
      VERSION \
      bin/bump \
      bin/bumpster \
      bumpster.sh \
      config.sh \
      lib/BUMPSTER_LOGO.ASCII \
      lib/functions.sh
    if [[ "$include_hook" == "true" ]]; then
      printf '%s\n' hooks/pre-bump
    fi
  } | LC_ALL=C sort)"
  actual_files="$(
    find "$target_home" -type f -print |
      sed "s#^$target_home/##" |
      LC_ALL=C sort
  )" || return 1

  assert_equal "$expected_files" "$actual_files" \
    "Installed runtime contains missing or unexpected files"
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
    "Install or update left a temporary directory behind"
}

test_clean_install() {
  local test_root="$suite_root/clean"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output
  local help_output

  mkdir -p "$home_dir" || return 1
  release_dir="$(create_release_fixture clean-release 0.9.0)" || return 1
  output="$(run_installer "$home_dir" "$target_home" "$release_dir" 2>&1)" ||
    fail "Clean install failed: $output" || return 1

  assert_equal "Bumpster version: 0.9.0" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Clean install reports the wrong version" || return 1
  help_output="$(
    HOME="$home_dir" \
      PATH="$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --help
  )" || fail "Installed runtime help failed" || return 1
  assert_contains "$help_output" "Bumpster 0.9.0" \
    "Installed runtime help reports the wrong version" || return 1
  assert_minimal_installation "$target_home" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_contains "$output" "Bumpster 0.9.0 installed" \
    "Clean install success is not reported"
}

test_legacy_migration_preserves_user_data() {
  local test_root="$suite_root/migration"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output
  local backup_runtime

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1
  printf 'GIT_MASTER_BRANCH="stable"\n' > "$home_dir/.bumpsterrc" ||
    return 1
  release_dir="$(create_release_fixture migration-release 0.9.0)" || return 1

  output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$release_dir" \
      "$target_home/bin:$runtime_path" 2>&1
  )" || fail "Legacy migration failed: $output" || return 1

  assert_equal "Bumpster version: 0.9.0" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Migrated installation reports the wrong version" || return 1
  assert_equal '#!/usr/bin/env bash
exit 0' "$(<"$target_home/hooks/pre-bump")" \
    "Legacy migration did not preserve the user hook" || return 1
  assert_equal 'GIT_MASTER_BRANCH="stable"' "$(<"$home_dir/.bumpsterrc")" \
    "Legacy migration changed the global configuration" || return 1
  assert_minimal_installation "$target_home" true || return 1

  backup_runtime="$(
    find "$home_dir" \
      -maxdepth 3 \
      -type f \
      -path '*/.bumpster.backup.0.8.0.*/runtime/VERSION' \
      -print
  )" || return 1
  assert_contains "$backup_runtime" ".bumpster.backup.0.8.0." \
    "Legacy migration did not retain an identifiable backup" || return 1
  assert_equal "0.8.0" "$(<"$backup_runtime")" \
    "Legacy migration backup has the wrong version" || return 1
  assert_contains "$output" "Previous installation backup:" \
    "Legacy migration did not report the backup path"
}

test_repeated_install_is_transactional() {
  local test_root="$suite_root/reinstall"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local backup_count

  mkdir -p "$home_dir" || return 1
  release_dir="$(create_release_fixture reinstall-release 0.9.0)" || return 1
  run_installer "$home_dir" "$target_home" "$release_dir" >/dev/null ||
    return 1
  mkdir -p "$target_home/hooks" || return 1
  printf '#!/usr/bin/env bash\nexit 7\n' > "$target_home/hooks/pre-bump" ||
    return 1

  run_installer \
    "$home_dir" \
    "$target_home" \
    "$release_dir" \
    "$target_home/bin:$runtime_path" >/dev/null || return 1

  assert_equal "Bumpster version: 0.9.0" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Repeated install reports the wrong version" || return 1
  assert_contains "$(<"$target_home/hooks/pre-bump")" "exit 7" \
    "Repeated install did not preserve the user hook" || return 1
  backup_count="$(
    find "$home_dir" \
      -maxdepth 1 \
      -type d \
      -name '.bumpster.backup.0.9.0.*' |
      wc -l |
      awk '{print $1}'
  )" || return 1
  assert_equal "1" "$backup_count" \
    "Repeated install did not create exactly one collision-safe backup"
}

test_download_failure_keeps_existing_installation() {
  local test_root="$suite_root/download-failure"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local output

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1

  if output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$test_root/missing-release" \
      "$target_home/bin:$runtime_path" 2>&1
  )"; then
    fail "Install unexpectedly succeeded without Release assets"
    return 1
  fi

  assert_equal "0.8.0" "$(<"$target_home/VERSION")" \
    "Download failure changed the existing installation" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_contains "$output" "Could not download SHA256SUMS." \
    "Download failure is not diagnosed"
}

test_corrupt_checksum_keeps_existing_installation() {
  local test_root="$suite_root/checksum-failure"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1
  release_dir="$(create_release_fixture checksum-release 0.9.0)" || return 1
  printf '%064d  bumpster-0.9.0.tar.gz\n' 0 \
    > "$release_dir/SHA256SUMS" || return 1

  if output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$release_dir" \
      "$target_home/bin:$runtime_path" 2>&1
  )"; then
    fail "Install unexpectedly accepted a corrupt checksum"
    return 1
  fi

  assert_equal "0.8.0" "$(<"$target_home/VERSION")" \
    "Checksum failure changed the existing installation" || return 1
  assert_contains "$output" "Runtime archive checksum mismatch." \
    "Checksum failure is not diagnosed"
}

test_corrupt_archive_keeps_existing_installation() {
  local test_root="$suite_root/archive-failure"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1
  release_dir="$(create_release_fixture corrupt-archive-release 0.9.0)" ||
    return 1
  printf 'corrupt\n' >> "$release_dir/bumpster-0.9.0.tar.gz" || return 1

  if output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$release_dir" \
      "$target_home/bin:$runtime_path" 2>&1
  )"; then
    fail "Install unexpectedly accepted a corrupt archive"
    return 1
  fi

  assert_equal "0.8.0" "$(<"$target_home/VERSION")" \
    "Corrupt archive changed the existing installation" || return 1
  assert_contains "$output" "Runtime archive checksum mismatch." \
    "Corrupt archive failure is not diagnosed"
}

test_unexpected_archive_file_is_rejected() {
  local test_root="$suite_root/archive-contents"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  create_legacy_installation "$target_home" || return 1
  release_dir="$(
    create_release_fixture contents-release 0.9.0 unexpected.txt
  )" || return 1

  if output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$release_dir" \
      "$target_home/bin:$runtime_path" 2>&1
  )"; then
    fail "Install unexpectedly accepted an extra archive file"
    return 1
  fi

  assert_equal "0.8.0" "$(<"$target_home/VERSION")" \
    "Archive validation failure changed the existing installation" || return 1
  assert_contains "$output" "contents do not match the whitelist" \
    "Archive contents failure is not diagnosed"
}

test_post_switch_failure_rolls_back() {
  local test_root="$suite_root/rollback"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local fake_bin="$test_root/fake-bin"
  local release_dir
  local output

  mkdir -p "$home_dir" "$fake_bin" || return 1
  create_legacy_installation "$target_home" || return 1
  release_dir="$(create_release_fixture rollback-release 0.9.0)" || return 1

  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *"/.bumpster/bin"*) exit 42 ;;\n'
    printf 'esac\n'
    printf 'exec /bin/mkdir "$@"\n'
  } > "$fake_bin/mkdir" || return 1
  chmod +x "$fake_bin/mkdir" || return 1

  if output="$(
    run_installer \
      "$home_dir" \
      "$target_home" \
      "$release_dir" \
      "$fake_bin:$target_home/bin:$runtime_path" 2>&1
  )"; then
    fail "Install unexpectedly succeeded after the injected switch failure"
    return 1
  fi

  assert_equal "0.8.0" "$(<"$target_home/VERSION")" \
    "Rollback did not restore the previous version" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_contains "$output" "Previous Bumpster installation restored." \
    "Rollback success is not reported" || return 1
  assert_equal "0" "$(
    find "$home_dir" \
      -maxdepth 1 \
      -type d \
      -name '.bumpster.backup.*' |
      wc -l |
      awk '{print $1}'
  )" "Rollback left an unnecessary backup directory"
}

test_self_update_uses_verified_assets() {
  local test_root="$suite_root/self-update"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_090
  local release_091
  local output

  mkdir -p "$home_dir" || return 1
  release_090="$(create_release_fixture update-release-090 0.9.0)" ||
    return 1
  release_091="$(create_release_fixture update-release-091 0.9.1)" ||
    return 1
  run_installer "$home_dir" "$target_home" "$release_090" >/dev/null ||
    return 1
  mkdir -p "$target_home/hooks" || return 1
  printf '#!/usr/bin/env bash\nexit 9\n' > "$target_home/hooks/pre-bump" ||
    return 1

  output="$(
    HOME="$home_dir" \
      BUMPSTER_RELEASE_DOWNLOAD_URL="$(release_url_for_directory "$release_091")" \
      BUMPSTER_TEST_ALLOW_FILE_RELEASES=true \
      PATH="$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --update 2>&1
  )" || fail "Self-update failed: $output" || return 1

  assert_equal "Bumpster version: 0.9.1" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Self-update reports the wrong version" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_contains "$(<"$target_home/hooks/pre-bump")" "exit 9" \
    "Self-update did not preserve the user hook" || return 1
  assert_contains "$output" "Bumpster updated to version 0.9.1." \
    "Self-update success is not reported" || return 1
  assert_equal "0.9.0" "$(<"$(
    find "$home_dir" \
      -maxdepth 3 \
      -type f \
      -path '*/.bumpster.backup.0.9.0.*/runtime/VERSION' \
      -print
  )")" "Self-update backup has the wrong version"
}

test_self_update_failure_rolls_back() {
  local test_root="$suite_root/self-update-rollback"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local fake_bin="$test_root/fake-bin"
  local release_090
  local release_091
  local output

  mkdir -p "$home_dir" "$fake_bin" || return 1
  release_090="$(create_release_fixture rollback-update-release-090 0.9.0)" ||
    return 1
  release_091="$(create_release_fixture rollback-update-release-091 0.9.1)" ||
    return 1
  run_installer "$home_dir" "$target_home" "$release_090" >/dev/null ||
    return 1

  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *"/.bumpster/bin"*) exit 42 ;;\n'
    printf 'esac\n'
    printf 'exec /bin/mkdir "$@"\n'
  } > "$fake_bin/mkdir" || return 1
  chmod +x "$fake_bin/mkdir" || return 1

  if output="$(
    HOME="$home_dir" \
      BUMPSTER_RELEASE_DOWNLOAD_URL="$(release_url_for_directory "$release_091")" \
      BUMPSTER_TEST_ALLOW_FILE_RELEASES=true \
      PATH="$fake_bin:$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --update 2>&1
  )"; then
    fail "Self-update unexpectedly succeeded after the injected switch failure"
    return 1
  fi

  assert_equal "Bumpster version: 0.9.0" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Failed self-update did not restore the previous version" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_contains "$output" "Previous Bumpster installation restored." \
    "Self-update rollback success is not reported" || return 1
  assert_equal "0" "$(
    find "$home_dir" \
      -maxdepth 1 \
      -type d \
      -name '.bumpster.backup.*' |
      wc -l |
      awk '{print $1}'
  )" "Self-update rollback left an unnecessary backup directory"
}

test_self_update_noop_is_clean() {
  local test_root="$suite_root/self-update-noop"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  release_dir="$(create_release_fixture noop-update-release 0.9.0)" ||
    return 1
  run_installer "$home_dir" "$target_home" "$release_dir" >/dev/null ||
    return 1

  output="$(
    HOME="$home_dir" \
      BUMPSTER_RELEASE_DOWNLOAD_URL="$(release_url_for_directory "$release_dir")" \
      BUMPSTER_TEST_ALLOW_FILE_RELEASES=true \
      PATH="$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --update 2>&1
  )" || fail "No-op self-update failed: $output" || return 1

  assert_contains "$output" "already using the latest version (0.9.0)" \
    "No-op self-update is not reported" || return 1
  assert_no_temporary_directories "$home_dir" || return 1
  assert_equal "0" "$(
    find "$home_dir" \
      -maxdepth 1 \
      -type d \
      -name '.bumpster.backup.*' |
      wc -l |
      awk '{print $1}'
  )" "No-op self-update created a backup"
}

test_self_update_rejects_downgrade() {
  local test_root="$suite_root/self-update-downgrade"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_090
  local release_091
  local output

  mkdir -p "$home_dir" || return 1
  release_090="$(create_release_fixture downgrade-release-090 0.9.0)" ||
    return 1
  release_091="$(create_release_fixture downgrade-release-091 0.9.1)" ||
    return 1
  run_installer "$home_dir" "$target_home" "$release_091" >/dev/null ||
    return 1

  if output="$(
    HOME="$home_dir" \
      BUMPSTER_RELEASE_DOWNLOAD_URL="$(release_url_for_directory "$release_090")" \
      BUMPSTER_TEST_ALLOW_FILE_RELEASES=true \
      PATH="$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --update 2>&1
  )"; then
    fail "Self-update unexpectedly accepted a downgrade"
    return 1
  fi

  assert_equal "Bumpster version: 0.9.1" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Rejected downgrade changed the installed version" || return 1
  assert_contains "$output" "Refusing to downgrade from 0.9.1 to 0.9.0." \
    "Rejected downgrade is not diagnosed" || return 1
  assert_no_temporary_directories "$home_dir"
}

test_homebrew_update_uses_package_manager() {
  local test_root="$suite_root/homebrew-update"
  local home_dir="$test_root/home"
  local target_home="$home_dir/.bumpster"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  release_dir="$(create_release_fixture homebrew-update-release 0.9.0)" ||
    return 1
  run_installer "$home_dir" "$target_home" "$release_dir" >/dev/null ||
    return 1

  if output="$(
    HOME="$home_dir" \
      BUMPSTER_INSTALL_METHOD=homebrew \
      BUMPSTER_RELEASE_DOWNLOAD_URL="https://example.invalid/releases/latest/download" \
      PATH="$target_home/bin:$runtime_path" \
      "$target_home/bin/bumpster" --update 2>&1
  )"; then
    fail "Homebrew-managed self-update unexpectedly succeeded"
    return 1
  fi

  assert_equal "Bumpster version: 0.9.0" \
    "$(installed_version "$home_dir" "$target_home")" \
    "Rejected Homebrew self-update changed the installed version" || return 1
  assert_contains "$output" "Use 'brew upgrade bumpster' to update." \
    "Homebrew update guidance is missing" || return 1
  assert_no_temporary_directories "$home_dir"
}

test_unsafe_home_is_rejected() {
  local test_root="$suite_root/unsafe-home"
  local home_dir="$test_root/home"
  local release_dir
  local output

  mkdir -p "$home_dir" || return 1
  printf 'keep\n' > "$home_dir/sentinel" || return 1
  release_dir="$(create_release_fixture unsafe-home-release 0.9.0)" ||
    return 1

  if output="$(
    run_installer "$home_dir" "$home_dir" "$release_dir" 2>&1
  )"; then
    fail "Installer unexpectedly accepted HOME as BUMPSTER_HOME"
    return 1
  fi

  assert_equal "keep" "$(<"$home_dir/sentinel")" \
    "Unsafe BUMPSTER_HOME validation changed HOME" || return 1
  assert_contains "$output" "Refusing to use a broad directory" \
    "Unsafe BUMPSTER_HOME rejection is not diagnosed"
}

run_test() {
  local name="$1"
  local test_function="$2"

  printf '  - %s\n' "$name"
  if "$test_function"; then
    passed=$((passed + 1))
    printf '    PASS\n'
  else
    failed=$((failed + 1))
    printf '    FAIL\n'
  fi
}

main() {
  if command -v shasum >/dev/null 2>&1; then
    sha256_command="shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256_command="sha256sum"
  else
    fail "shasum or sha256sum is required for install tests"
    return 1
  fi
  add_command_directory_to_runtime_path "$sha256_command" || return 1
  add_command_directory_to_runtime_path curl || return 1

  suite_root="$(
    mktemp -d "${TMPDIR:-/tmp}/bumpster-install-tests.XXXXXX"
  )" || return 1

  run_test "clean installation" test_clean_install
  run_test "migration from 0.8.0 preserves user data" \
    test_legacy_migration_preserves_user_data
  run_test "repeated installation remains transactional" \
    test_repeated_install_is_transactional
  run_test "download failure keeps the previous installation" \
    test_download_failure_keeps_existing_installation
  run_test "checksum failure keeps the previous installation" \
    test_corrupt_checksum_keeps_existing_installation
  run_test "corrupt archive keeps the previous installation" \
    test_corrupt_archive_keeps_existing_installation
  run_test "unexpected archive files are rejected" \
    test_unexpected_archive_file_is_rejected
  run_test "post-switch failure restores the previous installation" \
    test_post_switch_failure_rolls_back
  run_test "self-update uses verified Release assets" \
    test_self_update_uses_verified_assets
  run_test "failed self-update restores the previous installation" \
    test_self_update_failure_rolls_back
  run_test "current self-update is a clean no-op" \
    test_self_update_noop_is_clean
  run_test "self-update rejects a downgrade" \
    test_self_update_rejects_downgrade
  run_test "Homebrew-managed updates use the package manager" \
    test_homebrew_update_uses_package_manager
  run_test "unsafe BUMPSTER_HOME is rejected before mutation" \
    test_unsafe_home_is_rejected

  printf '  Install scenarios passed: %d\n' "$passed"
  printf '  Install scenarios failed: %d\n' "$failed"
  [[ "$failed" -eq 0 ]]
}

main "$@"
