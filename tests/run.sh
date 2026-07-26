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

assert_no_release_mutation() {
  local expected_head="$1"
  local expected_version="$2"
  local actual_head
  local actual_version
  local tags

  actual_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  actual_version="$(<"$fixture_worktree/VERSION")" || return 1
  tags="$(git -C "$fixture_worktree" tag --list)"

  assert_equal "$expected_head" "$actual_head" "HEAD changed after rejected release" || return 1
  assert_equal "$expected_version" "$actual_version" "VERSION changed after rejected release" || return 1
  assert_equal "" "$tags" "A tag was created after rejected release"
}

test_fixture_uses_local_bare_remote() {
  create_fixture "isolated-remote" || return 1

  assert_fixture_is_isolated ||
    fail "Fixture origin is not an isolated local bare repository"
}

test_patch_release_flow() {
  local local_version
  local dev_version
  local main_version
  local remote_dev_version
  local remote_main_version
  local current_branch
  local worktree_status

  create_fixture "patch-release" || return 1
  run_bumpster --patch

  assert_equal "0" "$cli_status" "Patch release failed: $cli_output" || return 1

  local_version="$(<"$fixture_worktree/VERSION")" || return 1
  dev_version="$(git -C "$fixture_worktree" show dev:VERSION)" || return 1
  main_version="$(git -C "$fixture_worktree" show main:VERSION)" || return 1
  remote_dev_version="$(git --git-dir="$fixture_origin" show refs/heads/dev:VERSION)" || return 1
  remote_main_version="$(git --git-dir="$fixture_origin" show refs/heads/main:VERSION)" || return 1
  current_branch="$(git -C "$fixture_worktree" branch --show-current)" || return 1
  worktree_status="$(git -C "$fixture_worktree" status --porcelain)" || return 1

  assert_equal "0.8.1" "$local_version" "Working tree has the wrong version" || return 1
  assert_equal "0.8.1" "$dev_version" "Development branch has the wrong version" || return 1
  assert_equal "0.8.1" "$main_version" "Main branch has the wrong version" || return 1
  assert_equal "0.8.1" "$remote_dev_version" "Remote development branch has the wrong version" || return 1
  assert_equal "0.8.1" "$remote_main_version" "Remote main branch has the wrong version" || return 1
  assert_equal "dev" "$current_branch" "CLI did not return to the configured branch" || return 1
  assert_equal "" "$worktree_status" "Working tree is dirty after release" || return 1
  assert_command_succeeds "Local release tag is missing" \
    git -C "$fixture_worktree" show-ref --verify --quiet refs/tags/v0.8.1 || return 1
  assert_command_succeeds "Remote release tag is missing" \
    git --git-dir="$fixture_origin" show-ref --verify --quiet refs/tags/v0.8.1
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
  assert_no_release_mutation "$initial_head" "0.8.0"
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
  assert_no_release_mutation "$initial_head" "0.8.0"
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
  assert_no_release_mutation "$initial_head" "0.8.0"
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
  run_test "dirty worktree is rejected without release mutations" test_dirty_worktree_is_rejected
  run_test "wrong starting branch is rejected without release mutations" test_wrong_starting_branch_is_rejected
  run_test "failing pre-hook is rejected without release mutations" test_failing_pre_hook_is_rejected_without_mutation

  printf '\nPassed: %d\nFailed: %d\n' "$passed" "$failed"
  [[ "$failed" -eq 0 ]]
}

main "$@"
