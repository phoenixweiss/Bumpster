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
passed=0
failed=0

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
  printf '    %s\n' "$*" >&2
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

assert_command_succeeds() {
  local message="$1"
  shift

  if ! "$@"; then
    fail "$message"
  fi
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
  local is_bare

  remote_url="$(git -C "$fixture_worktree" remote get-url origin)" || return 1
  is_bare="$(git --git-dir="$fixture_origin" rev-parse --is-bare-repository)" || return 1

  case "$remote_url" in
    "$suite_root"/*) ;;
    *) return 1 ;;
  esac

  [[ "$is_bare" == "true" ]]
}

run_bumpster() {
  cli_output="$(
    cd "$fixture_worktree" &&
      HOME="$fixture_home" \
      BUMPSTER_HOME="$project_root" \
      bash "$project_root/bumpster.sh" "$@" 2>&1
  )"
  cli_status=$?
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

test_fixture_uses_local_bare_remote() {
  create_fixture "isolated-remote" || return 1

  assert_fixture_is_isolated ||
    fail "Fixture origin is not an isolated local bare repository"
}

test_patch_release_flow() {
  create_fixture "patch-release" || return 1
  run_bumpster --patch
  assert_successful_release "0.8.1"
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

  actual_remote_dev="$(git --git-dir="$fixture_origin" rev-parse refs/heads/dev)" || return 1
  actual_remote_main="$(git --git-dir="$fixture_origin" rev-parse refs/heads/main)" || return 1
  assert_equal "$initial_remote_dev" "$actual_remote_dev" "Remote dev changed after rejected atomic push" || return 1
  assert_equal "$initial_remote_main" "$actual_remote_main" "Remote main changed after rejected atomic push" || return 1

  if git --git-dir="$fixture_origin" show-ref --verify --quiet refs/tags/v0.8.1; then
    fail "Remote tag was created after rejected atomic push"
  fi
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
  suite_root="$(mktemp -d "${TMPDIR:-/tmp}/bumpster-tests.XXXXXX")" ||
    fail "Could not create the test directory" || return 1

  run_test "fixture uses an isolated local bare remote" test_fixture_uses_local_bare_remote
  run_test "patch release updates and pushes dev, main and tag" test_patch_release_flow
  run_test "minor release resets patch and publishes the release" test_minor_release_flow
  run_test "major release resets minor and patch and publishes the release" test_major_release_flow
  run_test "dirty worktree is rejected without release mutations" test_dirty_worktree_is_rejected
  run_test "wrong starting branch is rejected without release mutations" test_wrong_starting_branch_is_rejected
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

  printf '\nPassed: %d\nFailed: %d\n' "$passed" "$failed"
  [[ "$failed" -eq 0 ]]
}

main "$@"
