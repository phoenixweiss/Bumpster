#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite_root=""
fixture_root=""
fixture_worktree=""
fixture_origin=""
fixture_home=""
cli_output=""
cli_status=0
test_path="$PATH"
passed=0
failed=0
sha256_command=""

cleanup() {
  if [[ "${KEEP_TEST_TMP:-false}" == "true" ]]; then
    if [[ -n "$suite_root" ]]; then
      printf 'Test files kept at %s\n' "$suite_root"
    fi
    return
  fi

  if [[ -n "$suite_root" && "$suite_root" != "/" && "$(basename "$suite_root")" == bumpster-tests.* ]]; then
    rm -rf -- "$suite_root"
  fi
}

trap cleanup EXIT INT TERM

fail() {
  local message="$*"
  local annotation_message

  printf '    %s\n' "$message" >&2

  if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    annotation_message="${message//'%'/'%25'}"
    annotation_message="${annotation_message//$'\r'/'%0D'}"
    annotation_message="${annotation_message//$'\n'/'%0A'}"
    printf '::error title=Bumpster integration test::%s\n' "$annotation_message"
  fi

  return 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values differ}"

  if [[ "$expected" != "$actual" ]]; then
    fail "$message (expected: '$expected', actual: '$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Expected text was not found}"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message (missing: '$needle')"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Unexpected text was found}"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$message (unexpected: '$needle')"
  fi
}

assert_command_succeeds() {
  local message="$1"
  shift

  if ! "$@"; then
    fail "$message"
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

create_fixture() {
  local name="$1"
  local initial_version="${2:-0.8.0}"

  fixture_root="$suite_root/$name"
  fixture_worktree="$fixture_root/worktree"
  fixture_origin="$fixture_root/origin.git"
  fixture_home="$fixture_root/home"

  mkdir -p "$fixture_worktree" "$fixture_home" || return 1
  git init -q --bare "$fixture_origin" || return 1
  git init -q "$fixture_worktree" || return 1
  git -C "$fixture_worktree" config user.name "Bumpster Tests" || return 1
  git -C "$fixture_worktree" config user.email "bumpster-tests@example.invalid" || return 1
  git -C "$fixture_worktree" checkout -q -b main || return 1

  printf '%s' "$initial_version" > "$fixture_worktree/VERSION" || return 1
  printf '# Fixture repository\n' > "$fixture_worktree/README.md" || return 1
  cp "$project_root/.bumpsterrc" "$fixture_worktree/.bumpsterrc" || return 1

  git -C "$fixture_worktree" add VERSION README.md .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m "Initialize fixture" || return 1
  git -C "$fixture_worktree" remote add origin "$fixture_origin" || return 1
  git -C "$fixture_worktree" push -q -u origin main || return 1
  git -C "$fixture_worktree" checkout -q -b dev || return 1
  git -C "$fixture_worktree" push -q -u origin dev || return 1

  assert_fixture_is_isolated
}

assert_fixture_is_isolated() {
  local remote_url
  local remote_path
  local expected_origin_path
  local expected_suite_path
  local is_bare

  remote_url="$(git -C "$fixture_worktree" remote get-url origin)" || return 1
  remote_path="$(cd "$remote_url" 2>/dev/null && pwd -P)" || return 1
  expected_origin_path="$(cd "$fixture_origin" && pwd -P)" || return 1
  expected_suite_path="$(cd "$suite_root" && pwd -P)" || return 1
  is_bare="$(git --git-dir="$fixture_origin" rev-parse --is-bare-repository)" || return 1

  case "$expected_origin_path" in
    "$expected_suite_path"/*) ;;
    *) return 1 ;;
  esac

  [[ "$remote_path" == "$expected_origin_path" && "$is_bare" == "true" ]]
}

run_bumpster() {
  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" "$@" 2>&1
  )"
  cli_status=$?
}

run_bumpster_with_home() {
  local runtime_home="$1"
  shift

  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$runtime_home" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" "$@" 2>&1
  )"
  cli_status=$?
}

run_bumpster_with_input() {
  local input="$1"
  shift

  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" "$@" <<< "$input" 2>&1
  )"
  cli_status=$?
}

create_feature_fixture() {
  local name="$1"

  create_fixture "$name" || return 1
  git -C "$fixture_worktree" checkout -q -b feature/example || return 1
  printf 'Committed feature change\n' > "$fixture_worktree/feature.txt" || return 1
  git -C "$fixture_worktree" add feature.txt || return 1
  git -C "$fixture_worktree" commit -q -m "Add fixture feature" || return 1
  git -C "$fixture_worktree" push -q -u origin feature/example
}

enable_package_sync() {
  printf '\nSYNC_WITH_PACKAGE_JSON="true"\n' >> "$fixture_worktree/.bumpsterrc" ||
    return 1
}

assert_release_state_unchanged() {
  local expected_head="$1"
  local expected_version="$2"
  local expected_tags="${3:-}"
  local actual_head
  local actual_version
  local tags

  actual_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  actual_version="$(<"$fixture_worktree/VERSION")" || return 1
  tags="$(git -C "$fixture_worktree" tag --list)"

  assert_equal "$expected_head" "$actual_head" "HEAD changed after rejected release" || return 1
  assert_equal "$expected_version" "$actual_version" "VERSION changed after rejected release" || return 1
  assert_equal "$expected_tags" "$tags" "Tags changed after rejected release"
}

assert_successful_release() {
  local expected_version="$1"
  local tag_name="v$expected_version"
  local local_version
  local dev_version
  local main_version
  local remote_dev_version
  local remote_main_version
  local current_branch
  local worktree_status

  assert_equal "0" "$cli_status" "Release failed: $cli_output" || return 1

  local_version="$(<"$fixture_worktree/VERSION")" || return 1
  dev_version="$(git -C "$fixture_worktree" show dev:VERSION)" || return 1
  main_version="$(git -C "$fixture_worktree" show main:VERSION)" || return 1
  remote_dev_version="$(git --git-dir="$fixture_origin" show refs/heads/dev:VERSION)" || return 1
  remote_main_version="$(git --git-dir="$fixture_origin" show refs/heads/main:VERSION)" || return 1
  current_branch="$(git -C "$fixture_worktree" branch --show-current)" || return 1
  worktree_status="$(git -C "$fixture_worktree" status --porcelain)" || return 1

  assert_equal "$expected_version" "$local_version" "Working tree has the wrong version" || return 1
  assert_equal "$expected_version" "$dev_version" "Development branch has the wrong version" || return 1
  assert_equal "$expected_version" "$main_version" "Main branch has the wrong version" || return 1
  assert_equal "$expected_version" "$remote_dev_version" "Remote development branch has the wrong version" || return 1
  assert_equal "$expected_version" "$remote_main_version" "Remote main branch has the wrong version" || return 1
  assert_equal "dev" "$current_branch" "CLI did not return to the configured branch" || return 1
  assert_equal "" "$worktree_status" "Working tree is dirty after release" || return 1
  assert_command_succeeds "Local release tag is missing" \
    git -C "$fixture_worktree" show-ref --verify --quiet "refs/tags/$tag_name" || return 1
  assert_command_succeeds "Remote release tag is missing" \
    git --git-dir="$fixture_origin" show-ref --verify --quiet "refs/tags/$tag_name"
}

create_remote_commit() {
  local branch_name="$1"
  local marker="${2:-Remote change}"
  local remote_worktree="$fixture_root/remote-$branch_name"

  git clone -q --branch "$branch_name" "$fixture_origin" "$remote_worktree" || return 1
  git -C "$remote_worktree" config user.name "Remote Bumpster Tests" || return 1
  git -C "$remote_worktree" config user.email "remote-bumpster-tests@example.invalid" || return 1
  printf '%s\n' "$marker" > "$remote_worktree/remote-change.txt" || return 1
  git -C "$remote_worktree" add remote-change.txt || return 1
  git -C "$remote_worktree" commit -q -m "$marker" || return 1
  git -C "$remote_worktree" push -q origin "$branch_name"
}

configure_custom_release_branches() {
  git -C "$fixture_worktree" checkout -q -b stable main || return 1
  git -C "$fixture_worktree" push -q -u origin stable || return 1
  git -C "$fixture_worktree" checkout -q -b integration dev || return 1
  git -C "$fixture_worktree" push -q -u origin integration
}

install_main_rejecting_hook() {
  local hook_path="$fixture_origin/hooks/pre-receive"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'while read -r old_value new_value ref_name; do\n'
    # The generated hook must contain the literal variable reference.
    # shellcheck disable=SC2016
    printf '  if [[ "$ref_name" == "refs/heads/main" ]]; then\n'
    printf '    exit 1\n'
    printf '  fi\n'
    printf 'done\n'
    printf 'exit 0\n'
  } > "$hook_path" || return 1
  chmod +x "$hook_path"
}

install_feature_delete_rejecting_hook() {
  local hook_path="$fixture_origin/hooks/pre-receive"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'zero_value="0000000000000000000000000000000000000000"\n'
    printf 'while read -r old_value new_value ref_name; do\n'
    # The generated hook must contain the literal variable references.
    # shellcheck disable=SC2016
    printf '  if [[ "$ref_name" == "refs/heads/feature/example" && "$new_value" == "$zero_value" ]]; then\n'
    printf '    exit 1\n'
    printf '  fi\n'
    printf 'done\n'
    printf 'exit 0\n'
  } > "$hook_path" || return 1
  chmod +x "$hook_path"
}

test_fixture_uses_local_bare_remote() {
  create_fixture "isolated-remote" || return 1

  assert_fixture_is_isolated ||
    fail "Fixture origin is not an isolated local bare repository"
}

test_runtime_archive_is_reproducible_and_minimal() {
  local version
  local output_one="$suite_root/runtime-one"
  local output_two="$suite_root/runtime-two"
  local archive_name
  local archive_one
  local archive_two
  local expected_entries
  local actual_entries
  local actual_checksum
  local expected_checksum
  local extract_dir="$suite_root/runtime-extract"
  local runtime_root
  local version_output

  version="$(git -C "$project_root" show HEAD:VERSION)" || return 1
  archive_name="bumpster-$version.tar.gz"
  archive_one="$output_one/$archive_name"
  archive_two="$output_two/$archive_name"

  "$project_root/scripts/build-runtime.sh" "$output_one" HEAD >/dev/null ||
    return 1
  "$project_root/scripts/build-runtime.sh" "$output_two" HEAD >/dev/null ||
    return 1

  assert_command_succeeds "Repeated runtime builds are not byte-for-byte reproducible" \
    cmp -s "$archive_one" "$archive_two" || return 1
  expected_checksum="$(awk '{print $1}' "$output_one/SHA256SUMS")" ||
    return 1
  actual_checksum="$(calculate_sha256 "$archive_one")" || return 1
  assert_equal "$expected_checksum" "$actual_checksum" \
    "Runtime checksum verification failed" || return 1

  expected_entries="$(
    printf '%s\n' \
      "bumpster-$version/" \
      "bumpster-$version/LICENSE" \
      "bumpster-$version/VERSION" \
      "bumpster-$version/bumpster.sh" \
      "bumpster-$version/config.sh" \
      "bumpster-$version/lib/" \
      "bumpster-$version/lib/BUMPSTER_LOGO.ASCII" \
      "bumpster-$version/lib/functions.sh"
  )"
  actual_entries="$(tar -tzf "$archive_one" | LC_ALL=C sort)" || return 1
  assert_equal "$expected_entries" "$actual_entries" \
    "Runtime archive contains missing or unexpected paths" || return 1

  mkdir -p "$extract_dir" || return 1
  tar -xzf "$archive_one" -C "$extract_dir" || return 1
  runtime_root="$extract_dir/bumpster-$version"
  version_output="$(
    HOME="$fixture_home" \
      BUMPSTER_HOME="$runtime_root" \
      bash "$runtime_root/bumpster.sh" --version
  )" || return 1
  assert_equal "Bumpster version: $version" "$version_output" \
    "Packaged runtime cannot report its version"
}

test_cli_delegates_release_execution() {
  local cli_source

  cli_source="$(<"$project_root/bumpster.sh")" || return 1
  assert_contains "$cli_source" 'set -o pipefail' \
    "CLI entry point does not enable pipeline failure handling" || return 1
  # The assertion intentionally searches for a literal shell variable.
  # shellcheck disable=SC2016
  assert_contains "$cli_source" 'run_release "$version_type"' \
    "CLI entry point does not delegate release execution" || return 1
  assert_not_contains "$cli_source" "git commit" \
    "CLI entry point still creates release commits directly" || return 1
  assert_not_contains "$cli_source" "git merge" \
    "CLI entry point still merges release branches directly" || return 1
  assert_not_contains "$cli_source" "git tag" \
    "CLI entry point still creates release tags directly" || return 1
  assert_not_contains "$cli_source" "git push" \
    "CLI entry point still publishes release refs directly"
}

test_install_and_update_suite() {
  bash "$project_root/tests/install.sh"
}

test_status_uses_default_configuration() {
  create_fixture "status-default-config" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" "Status command failed: $cli_output" || return 1
  assert_contains "$cli_output" "Current branch: dev" \
    "Status does not report the current branch" || return 1
  assert_contains "$cli_output" "You are on the development branch." \
    "Status does not recognize the default development branch" || return 1
  assert_contains "$cli_output" "Uncommitted changes: 0" \
    "Status reports the wrong worktree count" || return 1
  assert_contains "$cli_output" "Unpushed commits: 0" \
    "Status reports the wrong unpushed commit count" || return 1

  printf 'Local status change\n' > "$fixture_worktree/status.txt" || return 1
  git -C "$fixture_worktree" add status.txt || return 1
  git -C "$fixture_worktree" commit -q -m "Add local status change" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" \
    "Status failed with an unpushed commit: $cli_output" || return 1
  assert_contains "$cli_output" "Unpushed commits: 1" \
    "Status does not count commits ahead of the upstream"
}

test_status_uses_local_branch_configuration() {
  create_fixture "status-local-config" || return 1
  git -C "$fixture_worktree" checkout -q -b integration || return 1
  git -C "$fixture_worktree" push -q -u origin integration || return 1
  printf '%s\n' \
    'GIT_MASTER_BRANCH="stable"' \
    'GIT_DEVELOP_BRANCH="integration"' \
    > "$fixture_worktree/.bumpsterrc" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" "Configured status command failed: $cli_output" ||
    return 1
  assert_contains "$cli_output" "Current branch: integration" \
    "Status does not report the configured branch" || return 1
  assert_contains "$cli_output" "You are on the development branch." \
    "Status ignores the configured development branch" || return 1
  assert_not_contains "$cli_output" "You are on a feature branch." \
    "Configured development branch is classified as a feature branch"
}

test_status_uses_global_branch_configuration() {
  create_fixture "status-global-config" || return 1
  git -C "$fixture_worktree" checkout -q -b integration || return 1
  git -C "$fixture_worktree" push -q -u origin integration || return 1
  rm "$fixture_worktree/.bumpsterrc" || return 1
  printf '%s\n' \
    'GIT_MASTER_BRANCH="stable"' \
    'GIT_DEVELOP_BRANCH="integration"' \
    > "$fixture_home/.bumpsterrc" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" "Global-config status failed: $cli_output" ||
    return 1
  assert_contains "$cli_output" "Current branch: integration" \
    "Status does not report the global-config branch" || return 1
  assert_contains "$cli_output" "You are on the development branch." \
    "Status ignores the global development branch" || return 1
  assert_not_contains "$cli_output" "You are on a feature branch." \
    "Global development branch is classified as a feature branch"
}

test_status_rejects_non_repository() {
  local non_repository

  create_fixture "status-non-repository" || return 1
  non_repository="$fixture_root/not-a-repository"
  mkdir -p "$non_repository" || return 1

  cli_output="$(
    cd "$non_repository" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" --status 2>&1
  )"
  cli_status=$?

  [[ "$cli_status" -ne 0 ]] ||
    fail "Status unexpectedly succeeded outside a Git repository" || return 1
  assert_contains "$cli_output" "Git repository not found." \
    "Status repository error is unclear" || return 1
  assert_not_contains "$cli_output" "fatal:" \
    "Status exposes raw Git errors outside a repository"
}

test_status_handles_missing_upstream() {
  create_fixture "status-missing-upstream" || return 1
  git -C "$fixture_worktree" branch --unset-upstream dev || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" \
    "Status failed without an upstream branch: $cli_output" || return 1
  assert_contains "$cli_output" \
    "Unpushed commits: unavailable (no upstream branch)." \
    "Status does not explain the missing upstream" || return 1
  assert_not_contains "$cli_output" "fatal:" \
    "Status exposes raw Git errors without an upstream"
}

test_local_config_takes_priority_over_global_config() {
  create_fixture "config-local-priority" || return 1
  git -C "$fixture_worktree" checkout -q -b integration || return 1
  git -C "$fixture_worktree" push -q -u origin integration || return 1
  printf 'GIT_DEVELOP_BRANCH="dev"\n' > "$fixture_home/.bumpsterrc" || return 1
  printf 'GIT_DEVELOP_BRANCH="integration"\n' \
    > "$fixture_worktree/.bumpsterrc" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" "Local-priority status failed: $cli_output" ||
    return 1
  assert_contains "$cli_output" "You are on the development branch." \
    "Global configuration overrode the selected local configuration"
}

test_config_file_and_environment_precedence() {
  create_fixture "config-environment-precedence" || return 1
  git -C "$fixture_worktree" checkout -q -b integration || return 1
  git -C "$fixture_worktree" push -q -u origin integration || return 1
  printf 'ENABLE_LOGGING="false"\n' > "$fixture_worktree/.bumpsterrc" ||
    return 1

  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      GIT_DEVELOP_BRANCH="integration" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" --status 2>&1
  )"
  cli_status=$?

  assert_equal "0" "$cli_status" "Environment-backed status failed: $cli_output" ||
    return 1
  assert_contains "$cli_output" "You are on the development branch." \
    "Environment did not supply a value omitted by the selected config" ||
    return 1

  printf 'GIT_DEVELOP_BRANCH="dev"\n' > "$fixture_worktree/.bumpsterrc" ||
    return 1
  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      GIT_DEVELOP_BRANCH="integration" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" --status 2>&1
  )"
  cli_status=$?

  assert_equal "0" "$cli_status" "File-priority status failed: $cli_output" ||
    return 1
  assert_contains "$cli_output" "You are on a feature branch." \
    "Environment overrode a value assigned by the selected config"
}

test_invalid_selected_config_is_rejected() {
  create_fixture "config-load-failure" || return 1
  printf 'false\n' > "$fixture_worktree/.bumpsterrc" || return 1

  run_bumpster --status

  [[ "$cli_status" -ne 0 ]] ||
    fail "Status unexpectedly ignored a selected config failure" || return 1
  assert_contains "$cli_output" "Failed to load configuration from" \
    "Config load failure is unclear" || return 1
  assert_not_contains "$cli_output" "Current branch:" \
    "Status continued after the selected config failed"
}

test_local_config_write_failure_is_not_reported_as_success() {
  create_fixture "config-write-failure" || return 1
  rm "$fixture_worktree/.bumpsterrc" || return 1
  mkdir "$fixture_worktree/.bumpsterrc" || return 1

  run_bumpster_with_input $'\n\n\n\n\n\n\n\n\n' --create-local-config

  [[ "$cli_status" -ne 0 ]] ||
    fail "Local config creation unexpectedly succeeded for a directory target" ||
    return 1
  assert_contains "$cli_output" "Could not create local configuration file" \
    "Local config write failure is unclear" || return 1
  assert_not_contains "$cli_output" "successfully created" \
    "Failed local config creation was reported as successful"
}

test_logging_failure_warns_without_failing_read_only_command() {
  create_fixture "logging-write-failure" || return 1
  mkdir "$fixture_root/log-target" || return 1
  printf '%s\n' \
    'ENABLE_LOGGING="true"' \
    "LOG_FILE=\"$fixture_root/log-target\"" \
    > "$fixture_worktree/.bumpsterrc" || return 1

  run_bumpster --status

  assert_equal "0" "$cli_status" \
    "Optional logging failure broke status: $cli_output" || return 1
  assert_contains "$cli_output" "Could not write log file" \
    "Optional logging failure has no clear warning" || return 1
  assert_contains "$cli_output" "Current branch: dev" \
    "Status stopped after the optional logging failure"
}

test_custom_release_branches_and_before_after_options() {
  local remote_tag_commit

  create_fixture "custom-release-branches" || return 1
  configure_custom_release_branches || return 1
  git -C "$fixture_worktree" checkout -q -b release-work || return 1
  printf '%s\n' \
    'GIT_MASTER_BRANCH="stable"' \
    'GIT_DEVELOP_BRANCH="integration"' \
    'BEFORE_BUMP_BRANCH="release-work"' \
    'AFTER_BUMP_BRANCH="release-work"' \
    > "$fixture_worktree/.bumpsterrc" || return 1
  git -C "$fixture_worktree" add .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m "Configure custom release branches" ||
    return 1

  run_bumpster --patch

  assert_equal "0" "$cli_status" "Custom release failed: $cli_output" || return 1
  assert_equal "release-work" \
    "$(git -C "$fixture_worktree" branch --show-current)" \
    "Release did not return to AFTER_BUMP_BRANCH" || return 1
  assert_equal "0.8.1" \
    "$(git -C "$fixture_worktree" show integration:VERSION)" \
    "Configured development branch has the wrong version" || return 1
  assert_equal "0.8.1" \
    "$(git -C "$fixture_worktree" show stable:VERSION)" \
    "Configured release branch has the wrong version" || return 1
  assert_equal "$(git -C "$fixture_worktree" rev-parse integration)" \
    "$(git --git-dir="$fixture_origin" rev-parse refs/heads/integration)" \
    "Configured development branch was not published" || return 1
  assert_equal "$(git -C "$fixture_worktree" rev-parse stable)" \
    "$(git --git-dir="$fixture_origin" rev-parse refs/heads/stable)" \
    "Configured release branch was not published" || return 1
  remote_tag_commit="$(
    git --git-dir="$fixture_origin" rev-list -n 1 refs/tags/v0.8.1
  )" || return 1
  assert_equal "$(git -C "$fixture_worktree" rev-parse integration)" \
    "$remote_tag_commit" "Custom release tag points to the wrong commit"
}

test_missing_after_branch_falls_back_to_configured_development() {
  create_fixture "missing-after-branch" || return 1
  configure_custom_release_branches || return 1
  printf '%s\n' \
    'GIT_MASTER_BRANCH="stable"' \
    'GIT_DEVELOP_BRANCH="integration"' \
    'BEFORE_BUMP_BRANCH="integration"' \
    'AFTER_BUMP_BRANCH="missing-return-branch"' \
    > "$fixture_worktree/.bumpsterrc" || return 1
  git -C "$fixture_worktree" add .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m "Configure missing return branch" ||
    return 1

  run_bumpster --patch

  assert_equal "0" "$cli_status" \
    "Release with missing return branch failed: $cli_output" || return 1
  assert_equal "integration" \
    "$(git -C "$fixture_worktree" branch --show-current)" \
    "Missing AFTER_BUMP_BRANCH did not fall back to configured development"
}

test_custom_release_defaults_to_configured_development() {
  create_fixture "custom-release-default-branches" || return 1
  configure_custom_release_branches || return 1
  printf '%s\n' \
    'GIT_MASTER_BRANCH="stable"' \
    'GIT_DEVELOP_BRANCH="integration"' \
    > "$fixture_worktree/.bumpsterrc" || return 1
  git -C "$fixture_worktree" add .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m "Configure custom release defaults" ||
    return 1

  run_bumpster --patch

  assert_equal "0" "$cli_status" \
    "Custom release defaults failed: $cli_output" || return 1
  assert_equal "integration" \
    "$(git -C "$fixture_worktree" branch --show-current)" \
    "Before/after defaults did not follow configured development" || return 1
  assert_equal "0.8.1" \
    "$(git --git-dir="$fixture_origin" show refs/heads/integration:VERSION)" \
    "Configured development branch was not released" || return 1
  assert_equal "0.8.1" \
    "$(git --git-dir="$fixture_origin" show refs/heads/stable:VERSION)" \
    "Configured release branch was not updated"
}

test_hooks_use_project_priority_and_version_environment() {
  local runtime_home
  local project_hook_dir
  local global_hook_dir
  local hook_log

  create_fixture "hooks-priority-and-versions" || return 1
  runtime_home="$fixture_root/runtime-home"
  project_hook_dir="$fixture_worktree/.bumpster/hooks"
  global_hook_dir="$runtime_home/hooks"
  hook_log="$fixture_root/hooks.log"
  mkdir -p "$project_hook_dir" "$global_hook_dir" || return 1
  cp "$project_root/VERSION" "$runtime_home/VERSION" || return 1
  printf '/.bumpster/\n' >> "$fixture_worktree/.git/info/exclude" || return 1

  {
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016
    printf 'printf "global-pre:%%s:%%s\\n" "$BUMPSTER_PREV_VERSION" "$BUMPSTER_NEW_VERSION" > %q\n' \
      "$hook_log"
  } > "$global_hook_dir/pre-bump" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016
    printf 'printf "project-pre:%%s:%%s\\n" "$BUMPSTER_PREV_VERSION" "$BUMPSTER_NEW_VERSION" > %q\n' \
      "$hook_log"
  } > "$project_hook_dir/pre-bump" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016
    printf 'printf "project-post:%%s:%%s\\n" "$BUMPSTER_PREV_VERSION" "$BUMPSTER_NEW_VERSION" >> %q\n' \
      "$hook_log"
  } > "$project_hook_dir/post-bump" || return 1
  chmod +x \
    "$global_hook_dir/pre-bump" \
    "$project_hook_dir/pre-bump" \
    "$project_hook_dir/post-bump" || return 1

  run_bumpster_with_home "$runtime_home" --patch

  assert_successful_release "0.8.1" || return 1
  assert_equal $'project-pre:0.8.0:0.8.1\nproject-post:0.8.0:0.8.1' \
    "$(<"$hook_log")" \
    "Hooks did not use project priority or receive both versions"
}

test_clean_feature_branch_is_closed() {
  local current_branch
  local remote_feature_content

  create_feature_fixture "close-clean-feature" || return 1

  run_bumpster_with_input "n" --close-feature

  assert_equal "0" "$cli_status" "Clean feature close failed: $cli_output" || return 1
  current_branch="$(git -C "$fixture_worktree" branch --show-current)" || return 1
  remote_feature_content="$(
    git --git-dir="$fixture_origin" show refs/heads/dev:feature.txt
  )" || return 1
  assert_equal "dev" "$current_branch" "Feature close did not finish on dev" || return 1
  assert_equal "Committed feature change" "$remote_feature_content" \
    "Committed feature change was not pushed to dev" || return 1
  assert_command_succeeds "Retained feature branch is missing" \
    git -C "$fixture_worktree" show-ref --verify --quiet refs/heads/feature/example
}

test_create_feature_reports_unresolved_head() {
  local empty_repository

  create_fixture "create-feature-unresolved-head" || return 1
  empty_repository="$fixture_root/empty-repository"
  git init -q "$empty_repository" || return 1

  cli_output="$(
    cd "$empty_repository" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      PATH="$test_path" \
      bash "$project_root/bumpster.sh" --create-feature 2>&1
  )"
  cli_status=$?

  [[ "$cli_status" -ne 0 ]] ||
    fail "Feature creation unexpectedly succeeded without a resolvable HEAD" ||
    return 1
  assert_contains "$cli_output" "Could not determine the current branch." \
    "Feature creation masks an unresolved HEAD" || return 1
  assert_not_contains "$cli_output" "fatal:" \
    "Feature creation exposes raw Git errors for an unresolved HEAD"
}

test_dirty_feature_decline_is_rejected_without_mutation() {
  local initial_branch
  local initial_dev
  local initial_status

  create_feature_fixture "close-dirty-decline" || return 1
  printf 'Uncommitted feature change\n' >> "$fixture_worktree/README.md" || return 1
  initial_branch="$(git -C "$fixture_worktree" branch --show-current)" || return 1
  initial_dev="$(git -C "$fixture_worktree" rev-parse dev)" || return 1
  initial_status="$(git -C "$fixture_worktree" status --porcelain)" || return 1

  run_bumpster_with_input "n" --close-feature

  [[ "$cli_status" -ne 0 ]] ||
    fail "Dirty feature close unexpectedly continued without a stash" || return 1
  assert_contains "$cli_output" "Feature closing requires a clean working tree." \
    "Dirty feature rejection is unclear" || return 1
  assert_equal "$initial_branch" "$(git -C "$fixture_worktree" branch --show-current)" \
    "Branch changed after declining stash" || return 1
  assert_equal "$initial_dev" "$(git -C "$fixture_worktree" rev-parse dev)" \
    "Development branch changed after declining stash" || return 1
  assert_equal "$initial_status" "$(git -C "$fixture_worktree" status --porcelain)" \
    "Working tree changed after declining stash"
}

test_existing_stash_is_untouched_by_clean_feature_close() {
  local existing_stash_oid
  local remaining_stashes

  create_feature_fixture "close-keeps-existing-stash" || return 1
  printf 'Existing stashed change\n' >> "$fixture_worktree/README.md" || return 1
  git -C "$fixture_worktree" stash push -q \
    -m "Auto-stash before closing feature branch" || return 1
  existing_stash_oid="$(
    git -C "$fixture_worktree" rev-parse refs/stash
  )" || return 1

  run_bumpster_with_input "n" --close-feature

  assert_equal "0" "$cli_status" "Clean feature close failed: $cli_output" || return 1
  remaining_stashes="$(
    git -C "$fixture_worktree" stash list --format='%H'
  )" || return 1
  assert_equal "$existing_stash_oid" "$remaining_stashes" \
    "Existing stash was changed by a clean feature close" || return 1
  assert_equal "" "$(git -C "$fixture_worktree" status --porcelain)" \
    "Existing stash was unexpectedly applied"
}

test_operation_stash_is_restored_without_touching_older_stash() {
  local existing_stash_oid
  local remaining_stashes
  local remote_readme

  create_feature_fixture "close-restores-owned-stash" || return 1
  printf 'Older stashed change\n' >> "$fixture_worktree/README.md" || return 1
  git -C "$fixture_worktree" stash push -q -m "Older user stash" || return 1
  existing_stash_oid="$(
    git -C "$fixture_worktree" rev-parse refs/stash
  )" || return 1

  printf '# Staged feature draft\n' > "$fixture_worktree/README.md" || return 1
  git -C "$fixture_worktree" add README.md || return 1
  printf 'Untracked feature draft\n' > "$fixture_worktree/draft.txt" || return 1

  run_bumpster_with_input $'y\nn' --close-feature

  assert_equal "0" "$cli_status" "Stashed feature close failed: $cli_output" || return 1
  assert_equal "dev" "$(git -C "$fixture_worktree" branch --show-current)" \
    "Stashed changes were not restored on dev" || return 1
  assert_equal "# Staged feature draft" "$(<"$fixture_worktree/README.md")" \
    "Tracked feature draft was not restored" || return 1
  assert_equal "Untracked feature draft" "$(<"$fixture_worktree/draft.txt")" \
    "Untracked feature draft was not restored" || return 1
  assert_contains "$(git -C "$fixture_worktree" diff --cached --name-only)" "README.md" \
    "Staged state was not restored" || return 1
  remaining_stashes="$(
    git -C "$fixture_worktree" stash list --format='%H'
  )" || return 1
  assert_equal "$existing_stash_oid" "$remaining_stashes" \
    "Operation-owned stash was not removed exactly" || return 1
  remote_readme="$(
    git --git-dir="$fixture_origin" show refs/heads/dev:README.md
  )" || return 1
  assert_equal "# Fixture repository" "$remote_readme" \
    "Uncommitted feature draft leaked into remote dev"
}

test_close_from_development_branch_does_not_create_stash() {
  local initial_status

  create_fixture "close-from-dev" || return 1
  printf 'Uncommitted development change\n' >> "$fixture_worktree/README.md" || return 1
  initial_status="$(git -C "$fixture_worktree" status --porcelain)" || return 1

  run_bumpster --close-feature

  [[ "$cli_status" -ne 0 ]] ||
    fail "Feature close unexpectedly continued from dev" || return 1
  assert_contains "$cli_output" "Cannot close a feature branch from 'dev'." \
    "Development branch rejection is unclear" || return 1
  assert_equal "$initial_status" "$(git -C "$fixture_worktree" status --porcelain)" \
    "Working tree changed after close was rejected on dev" || return 1
  assert_equal "" "$(git -C "$fixture_worktree" stash list)" \
    "A stash was created before validating the current branch"
}

test_failed_feature_push_preserves_operation_stash() {
  local existing_stash_oid
  local created_stash_oid
  local remaining_stashes
  local initial_remote_dev

  create_feature_fixture "close-push-failure" || return 1
  printf 'Older stashed change\n' >> "$fixture_worktree/README.md" || return 1
  git -C "$fixture_worktree" stash push -q -m "Older user stash" || return 1
  existing_stash_oid="$(
    git -C "$fixture_worktree" rev-parse refs/stash
  )" || return 1
  printf 'Uncommitted feature change\n' >> "$fixture_worktree/README.md" || return 1
  printf 'Untracked feature change\n' > "$fixture_worktree/draft.txt" || return 1
  initial_remote_dev="$(git --git-dir="$fixture_origin" rev-parse refs/heads/dev)" ||
    return 1
  git -C "$fixture_worktree" remote set-url --push origin \
    "$fixture_root/unreachable.git" || return 1

  run_bumpster_with_input "y" --close-feature

  [[ "$cli_status" -ne 0 ]] ||
    fail "Feature close unexpectedly succeeded with an unreachable push URL" || return 1
  assert_contains "$cli_output" "Failed to push changes to remote." \
    "Feature push failure is unclear" || return 1
  assert_contains "$cli_output" "remain preserved in stash commit" \
    "Preserved operation stash is not reported" || return 1
  created_stash_oid="$(git -C "$fixture_worktree" rev-parse refs/stash)" || return 1
  assert_contains "$cli_output" "$created_stash_oid" \
    "Feature failure does not identify the exact operation stash" || return 1
  remaining_stashes="$(
    git -C "$fixture_worktree" stash list --format='%H'
  )" || return 1
  assert_contains "$remaining_stashes" "$created_stash_oid" \
    "Operation stash was lost after push failure" || return 1
  assert_contains "$remaining_stashes" "$existing_stash_oid" \
    "Older stash was lost after push failure" || return 1
  assert_equal "" "$(git -C "$fixture_worktree" status --porcelain)" \
    "Stashed changes leaked back into the failed close worktree" || return 1
  assert_equal "$initial_remote_dev" \
    "$(git --git-dir="$fixture_origin" rev-parse refs/heads/dev)" \
    "Remote dev changed despite the failed push"
}

test_failed_remote_feature_deletion_is_not_reported_as_success() {
  create_feature_fixture "failed-remote-feature-delete" || return 1
  install_feature_delete_rejecting_hook || return 1

  run_bumpster_with_input "y" --close-feature

  assert_equal "0" "$cli_status" \
    "Feature close failed after a non-critical remote deletion error: $cli_output" ||
    return 1
  assert_contains "$cli_output" "Failed to delete remote branch 'feature/example'." \
    "Remote feature deletion failure is missing" || return 1
  assert_not_contains "$cli_output" "Remote branch 'feature/example' deleted." \
    "Failed remote feature deletion was reported as successful" || return 1
  assert_contains "$cli_output" "Local feature branch 'feature/example' deleted." \
    "Successful local feature deletion is not reported precisely" || return 1
  if git --git-dir="$fixture_origin" show-ref \
    --verify --quiet refs/heads/feature/example; then
    return 0
  fi
  fail "Rejected remote feature deletion still removed the remote branch"
}

test_release_notes_extract_version_section() {
  cli_output="$(bash "$project_root/scripts/release-notes.sh" "0.8.2" 2>&1)"
  cli_status=$?

  assert_equal "0" "$cli_status" "Release notes extraction failed" || return 1
  assert_contains "$cli_output" "one atomic push" \
    "Expected 0.8.2 release note is missing" || return 1
  assert_not_contains "$cli_output" "ShellCheck" \
    "Release notes included the Unreleased section"
}

test_release_notes_reject_missing_version() {
  cli_output="$(bash "$project_root/scripts/release-notes.sh" "9.9.9" 2>&1)"
  cli_status=$?

  [[ "$cli_status" -ne 0 ]] || fail "Missing CHANGELOG version unexpectedly succeeded" || return 1
  assert_contains "$cli_output" "No CHANGELOG section found for version 9.9.9." \
    "Missing CHANGELOG version error is unclear"
}

test_package_sync_updates_only_root_version_atomically() {
  local package_values
  local initial_mode
  local updated_mode
  local temporary_files

  create_fixture "package-root-version" || return 1
  enable_package_sync || return 1
  {
    printf '{\n'
    printf '  "name": "fixture-package",\n'
    printf '  "version": "0.8.0",\n'
    printf '  "metadata": {\n'
    printf '    "version": "9.9.9"\n'
    printf '  },\n'
    printf '  "versionLabel": "keep-me"\n'
    printf '}\n'
  } > "$fixture_worktree/package.json" || return 1
  initial_mode="$(
    node -e 'console.log(require("fs").statSync(process.argv[1]).mode & 0o777)' \
      "$fixture_worktree/package.json"
  )" || return 1
  git -C "$fixture_worktree" add .bumpsterrc package.json || return 1
  git -C "$fixture_worktree" commit -q -m "Add fixture package" || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1" || return 1
  package_values="$(
    node -e '
      const data = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      console.log([data.version, data.metadata.version, data.versionLabel].join("|"));
    ' "$fixture_worktree/package.json"
  )" || return 1
  assert_equal "0.8.1|9.9.9|keep-me" "$package_values" \
    "Package sync changed a non-root version value" || return 1
  updated_mode="$(
    node -e 'console.log(require("fs").statSync(process.argv[1]).mode & 0o777)' \
      "$fixture_worktree/package.json"
  )" || return 1
  assert_equal "$initial_mode" "$updated_mode" \
    "Atomic package replacement changed file permissions" || return 1
  temporary_files="$(
    find "$fixture_worktree" -maxdepth 1 -name '.package.json.bumpster-*.tmp' -print
  )" || return 1
  assert_equal "" "$temporary_files" "Package sync left a temporary file behind"
}

test_package_sync_adds_missing_root_version() {
  local package_values

  create_fixture "package-missing-root-version" || return 1
  enable_package_sync || return 1
  {
    printf '{\n'
    printf '  "name": "fixture-package",\n'
    printf '  "metadata": {\n'
    printf '    "version": "9.9.9"\n'
    printf '  }\n'
    printf '}\n'
  } > "$fixture_worktree/package.json" || return 1
  git -C "$fixture_worktree" add .bumpsterrc package.json || return 1
  git -C "$fixture_worktree" commit -q -m "Add versionless fixture package" ||
    return 1

  run_bumpster --patch

  assert_successful_release "0.8.1" || return 1
  package_values="$(
    node -e '
      const data = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      console.log([data.version, data.metadata.version].join("|"));
    ' "$fixture_worktree/package.json"
  )" || return 1
  assert_equal "0.8.1|9.9.9" "$package_values" \
    "Package sync did not add only the root version"
}

test_invalid_package_json_is_rejected_before_release_mutation() {
  local initial_head
  local initial_package

  create_fixture "package-invalid-json" || return 1
  enable_package_sync || return 1
  printf '{"name":"fixture","version":"0.8.0",}\n' \
    > "$fixture_worktree/package.json" || return 1
  git -C "$fixture_worktree" add .bumpsterrc package.json || return 1
  git -C "$fixture_worktree" commit -q -m "Add invalid fixture package" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  initial_package="$(<"$fixture_worktree/package.json")" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] ||
    fail "Release unexpectedly accepted invalid package.json" || return 1
  assert_contains "$cli_output" "Invalid package.json:" \
    "Invalid package.json parse error is missing" || return 1
  assert_contains "$cli_output" "package.json cannot be synchronized safely." \
    "Invalid package.json release error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0" || return 1
  assert_equal "$initial_package" "$(<"$fixture_worktree/package.json")" \
    "Invalid package.json changed before release rejection"
}

test_non_string_package_version_is_rejected_before_release_mutation() {
  local initial_head

  create_fixture "package-non-string-version" || return 1
  enable_package_sync || return 1
  printf '{"name":"fixture","version":800}\n' \
    > "$fixture_worktree/package.json" || return 1
  git -C "$fixture_worktree" add .bumpsterrc package.json || return 1
  git -C "$fixture_worktree" commit -q -m "Add invalid package version" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] ||
    fail "Release unexpectedly accepted a non-string package version" || return 1
  assert_contains "$cli_output" "the root version field must be a string" \
    "Non-string package version error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_release_metadata_matches_published_refs() {
  local release_commit

  create_fixture "release-metadata" || return 1
  run_bumpster --patch
  assert_successful_release "0.8.1" || return 1
  release_commit="$(git -C "$fixture_worktree" rev-list -n 1 v0.8.1)" || return 1

  cli_output="$(
    cd "$fixture_worktree" &&
      bash "$project_root/scripts/validate-release.sh" \
        v0.8.1 \
        "$release_commit" \
        main 2>&1
  )"
  cli_status=$?

  assert_equal "0" "$cli_status" "Valid release metadata was rejected" || return 1
  assert_equal "0.8.1" "$cli_output" "Release validation returned the wrong version" || return 1

  cli_output="$(
    cd "$fixture_worktree" &&
      bash "$project_root/scripts/validate-release.sh" \
        v0.8.1 \
        0000000000000000000000000000000000000000 \
        main 2>&1
  )"
  cli_status=$?

  [[ "$cli_status" -ne 0 ]] || fail "Mismatched release commit unexpectedly succeeded" || return 1
  assert_contains "$cli_output" "instead of workflow commit" \
    "Mismatched release commit error is unclear"
}

test_patch_release_flow() {
  create_fixture "patch-release" || return 1
  run_bumpster --patch
  assert_successful_release "0.8.1" || return 1
  assert_contains "$cli_output" "Release plan: 0.8.0 -> 0.8.1 (patch)." \
    "Release plan is missing from the action log" || return 1
  assert_contains "$cli_output" \
    "Release branches: start 'dev', development 'dev', release 'main', return 'dev'." \
    "Release branch plan is missing from the action log" || return 1
  assert_contains "$cli_output" "Already on branch 'dev'." \
    "Release log does not identify the unchanged development branch" || return 1
  assert_contains "$cli_output" "Switching to branch 'main'." \
    "Release log does not identify the release-branch transition" || return 1
  assert_contains "$cli_output" "Returning to branch 'dev'." \
    "Release log does not identify the final branch transition"
}

test_minor_release_flow() {
  create_fixture "minor-release" "1.2.3" || return 1
  run_bumpster --minor
  assert_successful_release "1.3.0"
}

test_major_release_flow() {
  create_fixture "major-release" "1.2.3" || return 1
  run_bumpster --major
  assert_successful_release "2.0.0"
}

test_dirty_worktree_is_rejected() {
  local initial_head

  create_fixture "dirty-worktree" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  printf 'Uncommitted change\n' > "$fixture_worktree/notes.txt" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with a dirty worktree" || return 1
  assert_contains "$cli_output" "Working tree contains unstaged changes. Aborting." \
    "Dirty worktree error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_wrong_starting_branch_is_rejected() {
  local initial_head

  create_fixture "wrong-branch" || return 1
  git -C "$fixture_worktree" checkout -q main || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded from main" || return 1
  assert_contains "$cli_output" "Version bumps must be run from 'dev'" \
    "Wrong starting branch error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_configured_release_branch_cannot_start_release() {
  local initial_head

  create_fixture "release-branch-start" || return 1
  git -C "$fixture_worktree" checkout -q main || return 1
  printf 'BEFORE_BUMP_BRANCH="main"\n' > "$fixture_worktree/.bumpsterrc" ||
    return 1
  git -C "$fixture_worktree" add .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m "Configure unsafe release start" ||
    return 1
  git -C "$fixture_worktree" push -q origin main || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] ||
    fail "Release unexpectedly started from the configured release branch" ||
    return 1
  assert_contains "$cli_output" \
    "BEFORE_BUMP_BRANCH must not be the configured release branch 'main'." \
    "Unsafe release-branch start error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_missing_version_file_is_rejected_without_mutation() {
  local initial_head

  create_fixture "missing-version" || return 1
  git -C "$fixture_worktree" rm -q VERSION || return 1
  git -C "$fixture_worktree" commit -q -m "Remove fixture version" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded without VERSION" || return 1
  assert_contains "$cli_output" "VERSION file not found." \
    "Missing VERSION error is unclear" || return 1
  assert_equal "$initial_head" "$(git -C "$fixture_worktree" rev-parse HEAD)" \
    "HEAD changed after missing VERSION was rejected"
}

test_invalid_version_is_rejected_without_mutation() {
  local invalid_version
  local initial_head

  for invalid_version in "1.2" "1.2.3.4" "01.2.3" "v1.2.3" "1.2.x" "1.2.3-rc.1"; do
    create_fixture "invalid-version-${invalid_version//[^a-zA-Z0-9]/-}" "$invalid_version" ||
      return 1
    initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

    run_bumpster --patch

    [[ "$cli_status" -ne 0 ]] ||
      fail "Release unexpectedly accepted VERSION '$invalid_version'" || return 1
    assert_contains "$cli_output" "VERSION must contain MAJOR.MINOR.PATCH" \
      "Invalid VERSION error is unclear for '$invalid_version'" || return 1
    assert_release_state_unchanged "$initial_head" "$invalid_version" || return 1
  done
}

test_missing_origin_is_rejected_without_mutation() {
  local initial_head

  create_fixture "missing-origin" || return 1
  git -C "$fixture_worktree" remote remove origin || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded without origin" || return 1
  assert_contains "$cli_output" "Remote 'origin' is not configured." \
    "Missing origin error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_unreachable_origin_is_rejected_without_mutation() {
  local initial_head

  create_fixture "unreachable-origin" || return 1
  git -C "$fixture_worktree" remote set-url origin "$fixture_root/unreachable.git" ||
    return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with unreachable origin" || return 1
  assert_contains "$cli_output" "Failed to query release refs from origin." \
    "Unreachable origin error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_missing_development_upstream_is_rejected_without_mutation() {
  local initial_head

  create_fixture "missing-dev-upstream" || return 1
  git -C "$fixture_worktree" branch --unset-upstream dev || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded without dev upstream" || return 1
  assert_contains "$cli_output" "Branch 'dev' must track 'origin/dev' before release." \
    "Missing dev upstream error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_wrong_development_upstream_is_rejected_without_mutation() {
  local initial_head

  create_fixture "wrong-dev-upstream" || return 1
  git -C "$fixture_worktree" branch --set-upstream-to=origin/main dev >/dev/null ||
    return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with wrong dev upstream" || return 1
  assert_contains "$cli_output" "Branch 'dev' tracks 'origin/main'; expected 'origin/dev'." \
    "Wrong dev upstream error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_wrong_main_upstream_is_rejected_without_mutation() {
  local initial_head

  create_fixture "wrong-main-upstream" || return 1
  git -C "$fixture_worktree" branch --set-upstream-to=origin/dev main >/dev/null ||
    return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with wrong main upstream" || return 1
  assert_contains "$cli_output" "Branch 'main' tracks 'origin/dev'; expected 'origin/main'." \
    "Wrong main upstream error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_unfetched_remote_development_is_rejected_without_mutation() {
  local initial_head

  create_fixture "unfetched-remote-dev" || return 1
  git -C "$fixture_worktree" config --unset-all remote.origin.fetch || return 1
  git -C "$fixture_worktree" config --add remote.origin.fetch \
    "+refs/heads/main:refs/remotes/origin/main" || return 1
  git -C "$fixture_worktree" update-ref -d refs/remotes/origin/dev || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded without fetched origin/dev" || return 1
  assert_contains "$cli_output" "Remote branch 'origin/dev' exists but was not fetched." \
    "Fetch refspec error is unclear" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_failing_pre_hook_is_rejected_without_mutation() {
  local initial_head
  local hook_path

  create_fixture "failing-pre-hook" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  hook_path="$fixture_worktree/.bumpster/hooks/pre-bump"

  mkdir -p "$(dirname "$hook_path")" || return 1
  printf '/.bumpster/\n' >> "$fixture_worktree/.git/info/exclude" || return 1
  printf '#!/usr/bin/env bash\nexit 42\n' > "$hook_path" || return 1
  chmod +x "$hook_path" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded after a failing pre-hook" || return 1
  assert_contains "$cli_output" "Hook 'pre-bump' failed." \
    "Pre-hook failure is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_existing_release_tag_is_rejected_without_mutation() {
  local initial_head

  create_fixture "existing-tag" || return 1
  git -C "$fixture_worktree" tag -a v0.8.1 -m "Existing release" || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with an existing tag" || return 1
  assert_contains "$cli_output" "Release tag 'v0.8.1' already exists" \
    "Existing tag error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0" "v0.8.1"
}

test_remote_development_ahead_is_rejected_without_mutation() {
  local initial_head

  create_fixture "remote-dev-ahead" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  create_remote_commit "dev" "Advance remote development" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded behind origin/dev" || return 1
  assert_contains "$cli_output" "Local branch 'dev' is behind or has diverged from 'origin/dev'" \
    "Remote development divergence error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_local_development_ahead_is_released() {
  create_fixture "local-dev-ahead" || return 1
  printf 'Ready for release\n' > "$fixture_worktree/feature.txt" || return 1
  git -C "$fixture_worktree" add feature.txt || return 1
  git -C "$fixture_worktree" commit -q -m "Add fixture feature" || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1"
}

test_remote_main_ahead_is_rejected_without_mutation() {
  local initial_head

  create_fixture "remote-main-ahead" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  create_remote_commit "main" "Advance remote main" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded behind origin/main" || return 1
  assert_contains "$cli_output" "Local branch 'main' does not match 'origin/main'" \
    "Remote main divergence error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_local_main_divergence_is_rejected_without_mutation() {
  local initial_head

  create_fixture "local-main-diverged" || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  git -C "$fixture_worktree" checkout -q main || return 1
  printf 'Local main change\n' > "$fixture_worktree/main-only.txt" || return 1
  git -C "$fixture_worktree" add main-only.txt || return 1
  git -C "$fixture_worktree" commit -q -m "Advance local main" || return 1
  git -C "$fixture_worktree" checkout -q dev || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with a divergent local main" || return 1
  assert_contains "$cli_output" "Local branch 'main' does not match 'origin/main'" \
    "Local main divergence error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_remote_only_main_is_checked_out_as_tracking_branch() {
  local upstream

  create_fixture "remote-only-main" || return 1
  git -C "$fixture_worktree" branch -D main >/dev/null || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1" || return 1
  upstream="$(git -C "$fixture_worktree" rev-parse --abbrev-ref 'main@{upstream}')" || return 1
  assert_equal "origin/main" "$upstream" "Remote-only main was not created as a tracking branch"
}

test_missing_remote_main_is_created_by_release() {
  create_fixture "missing-remote-main" || return 1
  git --git-dir="$fixture_origin" update-ref -d refs/heads/main || return 1
  git -C "$fixture_worktree" update-ref -d refs/remotes/origin/main || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1"
}

test_missing_local_and_remote_main_is_created_by_release() {
  create_fixture "missing-main-everywhere" || return 1
  git -C "$fixture_worktree" branch -D main >/dev/null || return 1
  git --git-dir="$fixture_origin" update-ref -d refs/heads/main || return 1
  git -C "$fixture_worktree" update-ref -d refs/remotes/origin/main || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1"
}

test_missing_remote_development_is_created_by_release() {
  create_fixture "missing-remote-dev" || return 1
  git --git-dir="$fixture_origin" update-ref -d refs/heads/dev || return 1
  git -C "$fixture_worktree" update-ref -d refs/remotes/origin/dev || return 1

  run_bumpster --patch

  assert_successful_release "0.8.1"
}

test_remote_only_release_tag_is_rejected_without_mutation() {
  local initial_head

  create_fixture "remote-only-tag" || return 1
  git -C "$fixture_worktree" tag -a v0.8.1 -m "Existing remote release" || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 || return 1
  git -C "$fixture_worktree" tag -d v0.8.1 >/dev/null || return 1
  initial_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded with a remote-only tag" || return 1
  assert_contains "$cli_output" "Release tag 'v0.8.1' already exists on origin" \
    "Remote-only tag error is missing" || return 1
  assert_release_state_unchanged "$initial_head" "0.8.0"
}

test_rejected_main_push_keeps_remote_release_atomic() {
  local initial_remote_dev
  local initial_remote_main
  local actual_remote_dev
  local actual_remote_main

  create_fixture "rejected-main-push" || return 1
  initial_remote_dev="$(git --git-dir="$fixture_origin" rev-parse refs/heads/dev)" || return 1
  initial_remote_main="$(git --git-dir="$fixture_origin" rev-parse refs/heads/main)" || return 1
  install_main_rejecting_hook || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Release unexpectedly succeeded after main push was rejected" || return 1
  assert_contains "$cli_output" "Failed to publish the release atomically" \
    "Atomic push failure is missing" || return 1
  assert_contains "$cli_output" "No automatic rollback was attempted" \
    "Preserved local state is not explained" || return 1
  assert_contains "$cli_output" "Remote release refs are unchanged from preflight." \
    "Remote recovery state is not verified" || return 1
  assert_contains "$cli_output" \
    "git push --atomic origin refs/heads/dev refs/heads/main refs/tags/v0.8.1" \
    "Safe atomic retry command is missing" || return 1

  actual_remote_dev="$(git --git-dir="$fixture_origin" rev-parse refs/heads/dev)" || return 1
  actual_remote_main="$(git --git-dir="$fixture_origin" rev-parse refs/heads/main)" || return 1
  assert_equal "$initial_remote_dev" "$actual_remote_dev" "Remote dev changed after rejected atomic push" || return 1
  assert_equal "$initial_remote_main" "$actual_remote_main" "Remote main changed after rejected atomic push" || return 1

  if git --git-dir="$fixture_origin" show-ref --verify --quiet refs/tags/v0.8.1; then
    fail "Remote tag was created after rejected atomic push"
  fi
}

test_failing_post_hook_reports_published_release() {
  local hook_path
  local remote_tag_commit

  create_fixture "failing-post-hook" || return 1
  hook_path="$fixture_worktree/.bumpster/hooks/post-bump"
  mkdir -p "$(dirname "$hook_path")" || return 1
  printf '/.bumpster/\n' >> "$fixture_worktree/.git/info/exclude" || return 1
  printf '#!/usr/bin/env bash\nexit 42\n' > "$hook_path" || return 1
  chmod +x "$hook_path" || return 1

  run_bumpster --patch

  [[ "$cli_status" -ne 0 ]] || fail "Failing post-hook unexpectedly returned success" || return 1
  assert_contains "$cli_output" "The release was published before this later step failed." \
    "Published release state is not explained" || return 1
  assert_not_contains "$cli_output" "the preserved release can be retried" \
    "Published release incorrectly suggests another push" || return 1
  remote_tag_commit="$(
    git --git-dir="$fixture_origin" rev-list -n 1 refs/tags/v0.8.1
  )" || return 1
  assert_equal "$(git -C "$fixture_worktree" rev-parse dev)" "$remote_tag_commit" \
    "Published release tag points to the wrong commit"
}

run_test() {
  local name="$1"
  local test_function="$2"

  printf '• %s\n' "$name"
  if "$test_function"; then
    passed=$((passed + 1))
    printf '  PASS\n'
  else
    failed=$((failed + 1))
    printf '  FAIL\n'
  fi
}

main() {
  local node_binary=""

  if command -v shasum >/dev/null 2>&1; then
    sha256_command="shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256_command="sha256sum"
  else
    fail "shasum or sha256sum is required for integration tests"
    return 1
  fi

  node_binary="$(command -v node 2>/dev/null || true)"
  if command -v asdf >/dev/null 2>&1; then
    node_binary="$(asdf which node 2>/dev/null || printf '%s' "$node_binary")"
  fi
  if [[ -n "$node_binary" ]]; then
    test_path="$(dirname "$node_binary"):$PATH"
  fi

  suite_root="$(mktemp -d "${TMPDIR:-/tmp}/bumpster-tests.XXXXXX")" ||
    fail "Could not create the test directory" || return 1

  run_test "fixture uses an isolated local bare remote" test_fixture_uses_local_bare_remote
  run_test "runtime archive is reproducible, minimal and executable" test_runtime_archive_is_reproducible_and_minimal
  run_test "CLI delegates release execution to the release functions" test_cli_delegates_release_execution
  run_test "install and update flows are transactional" test_install_and_update_suite
  run_test "status uses the default branch configuration" test_status_uses_default_configuration
  run_test "status uses local custom branch configuration" test_status_uses_local_branch_configuration
  run_test "status uses global custom branch configuration" test_status_uses_global_branch_configuration
  run_test "status rejects execution outside a Git repository" test_status_rejects_non_repository
  run_test "status handles a missing upstream without raw Git errors" test_status_handles_missing_upstream
  run_test "local configuration takes priority over global configuration" test_local_config_takes_priority_over_global_config
  run_test "configuration files and environment values have defined precedence" test_config_file_and_environment_precedence
  run_test "invalid selected configuration is rejected" test_invalid_selected_config_is_rejected
  run_test "local configuration write failures are not reported as success" test_local_config_write_failure_is_not_reported_as_success
  run_test "logging failures warn without failing read-only commands" test_logging_failure_warns_without_failing_read_only_command
  run_test "custom release branches honor before and after options" test_custom_release_branches_and_before_after_options
  run_test "missing after-bump branch falls back to configured development" test_missing_after_branch_falls_back_to_configured_development
  run_test "custom release defaults follow configured development" test_custom_release_defaults_to_configured_development
  run_test "hooks use project priority and receive both versions" test_hooks_use_project_priority_and_version_environment
  run_test "feature creation reports an unresolved HEAD" test_create_feature_reports_unresolved_head
  run_test "clean feature branch closes and pushes committed changes" test_clean_feature_branch_is_closed
  run_test "dirty feature close cannot continue without a stash" test_dirty_feature_decline_is_rejected_without_mutation
  run_test "clean feature close leaves existing stash untouched" test_existing_stash_is_untouched_by_clean_feature_close
  run_test "operation stash restores tracked and untracked changes only" test_operation_stash_is_restored_without_touching_older_stash
  run_test "close from development branch does not create a stash" test_close_from_development_branch_does_not_create_stash
  run_test "failed feature push preserves the exact operation stash" test_failed_feature_push_preserves_operation_stash
  run_test "failed remote feature deletion is not reported as success" test_failed_remote_feature_deletion_is_not_reported_as_success
  run_test "release notes extract only the requested CHANGELOG section" test_release_notes_extract_version_section
  run_test "release notes reject a version missing from CHANGELOG" test_release_notes_reject_missing_version
  run_test "package sync updates only the root version atomically" test_package_sync_updates_only_root_version_atomically
  run_test "package sync adds a missing root version" test_package_sync_adds_missing_root_version
  run_test "invalid package JSON is rejected before release mutation" test_invalid_package_json_is_rejected_before_release_mutation
  run_test "non-string package version is rejected before release mutation" test_non_string_package_version_is_rejected_before_release_mutation
  run_test "release metadata matches VERSION, tag, commit and origin/main" test_release_metadata_matches_published_refs
  run_test "patch release updates and pushes dev, main and tag" test_patch_release_flow
  run_test "minor release resets patch and publishes the release" test_minor_release_flow
  run_test "major release resets minor and patch and publishes the release" test_major_release_flow
  run_test "dirty worktree is rejected without release mutations" test_dirty_worktree_is_rejected
  run_test "wrong starting branch is rejected without release mutations" test_wrong_starting_branch_is_rejected
  run_test "configured release branch cannot start a release" test_configured_release_branch_cannot_start_release
  run_test "missing VERSION is rejected without release mutations" test_missing_version_file_is_rejected_without_mutation
  run_test "invalid semantic versions are rejected without release mutations" test_invalid_version_is_rejected_without_mutation
  run_test "missing origin is rejected without release mutations" test_missing_origin_is_rejected_without_mutation
  run_test "unreachable origin is rejected without release mutations" test_unreachable_origin_is_rejected_without_mutation
  run_test "missing development upstream is rejected without release mutations" test_missing_development_upstream_is_rejected_without_mutation
  run_test "wrong development upstream is rejected without release mutations" test_wrong_development_upstream_is_rejected_without_mutation
  run_test "wrong main upstream is rejected without release mutations" test_wrong_main_upstream_is_rejected_without_mutation
  run_test "unfetched remote development is rejected without release mutations" test_unfetched_remote_development_is_rejected_without_mutation
  run_test "failing pre-hook is rejected without release mutations" test_failing_pre_hook_is_rejected_without_mutation
  run_test "existing release tag is rejected without release mutations" test_existing_release_tag_is_rejected_without_mutation
  run_test "remote development ahead is rejected without release mutations" test_remote_development_ahead_is_rejected_without_mutation
  run_test "local development ahead is included in the release" test_local_development_ahead_is_released
  run_test "remote main ahead is rejected without release mutations" test_remote_main_ahead_is_rejected_without_mutation
  run_test "local main divergence is rejected without release mutations" test_local_main_divergence_is_rejected_without_mutation
  run_test "remote-only main becomes a local tracking branch" test_remote_only_main_is_checked_out_as_tracking_branch
  run_test "missing remote main is created by the release" test_missing_remote_main_is_created_by_release
  run_test "main missing locally and remotely is created by the release" test_missing_local_and_remote_main_is_created_by_release
  run_test "missing remote development is created by the release" test_missing_remote_development_is_created_by_release
  run_test "remote-only release tag is rejected without release mutations" test_remote_only_release_tag_is_rejected_without_mutation
  run_test "rejected main update leaves all remote release refs unchanged" test_rejected_main_push_keeps_remote_release_atomic
  run_test "failing post-hook reports the already published release" test_failing_post_hook_reports_published_release

  printf '\nPassed: %d\nFailed: %d\n' "$passed" "$failed"
  [[ "$failed" -eq 0 ]]
}

main "$@"
