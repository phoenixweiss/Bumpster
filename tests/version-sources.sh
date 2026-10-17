#!/usr/bin/env bash

# Variables and helpers are supplied by run.sh; generated hooks expand at runtime.
# shellcheck disable=SC2154,SC2016
# Sourced by run.sh: every Git mutation below targets its local bare fixtures.
remove_fixture_tag() {
  git -C "$fixture_worktree" tag -d "$1" >/dev/null || return 1
  git --git-dir="$fixture_origin" update-ref -d "refs/tags/$1"
}

publish_fixture_main() {
  git -C "$fixture_worktree" checkout -q main || return 1
  git -C "$fixture_worktree" merge -q --ff-only dev || return 1
  git -C "$fixture_worktree" push -q origin main || return 1
  git -C "$fixture_worktree" checkout -q dev
}

# Compare all tracked files, the index, local refs, and published refs after refusal.
assert_version_refusal() {
  local expected="$1" before_head before_tree before_refs before_index before_local
  shift
  before_head="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  before_tree="$(git -C "$fixture_worktree" diff HEAD)" || return 1
  before_index="$(git -C "$fixture_worktree" diff --cached)" || return 1
  before_refs="$(git --git-dir="$fixture_origin" show-ref)" || return 1
  before_local="$(git -C "$fixture_worktree" show-ref --heads --tags)" || return 1
  run_bumpster "$@"
  [[ "$cli_status" != 0 ]] || { fail "Accepted invalid release: $cli_output"; return 1; }
  assert_contains "$cli_output" "$expected" || return 1
  assert_equal "$before_head" "$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  assert_equal "$before_tree" "$(git -C "$fixture_worktree" diff HEAD)" || return 1
  assert_equal "$before_index" "$(git -C "$fixture_worktree" diff --cached)" || return 1
  assert_equal "$before_refs" "$(git --git-dir="$fixture_origin" show-ref)" || return 1
  assert_equal "$before_local" "$(git -C "$fixture_worktree" show-ref --heads --tags)"
}

test_version_source_bootstrap() {
  create_fixture source-bootstrap || return 1
  remove_fixture_tag v0.8.0 || return 1
  git -C "$fixture_worktree" rm -q .bumpsterrc || return 1
  git -C "$fixture_worktree" commit -q -m 'Use first-release defaults' || return 1
  assert_version_refusal 'Initial release requires an explicit' --patch || return 1
  [[ ! -e "$fixture_home/.bumpsterrc" ]] || fail "Refusal created global configuration" || return 1
  run_bumpster --patch --version-source version-file
  assert_successful_release 0.8.1 || return 1
  create_package_fixture source-package-bootstrap || return 1
  remove_fixture_tag ui/v0.1.0 || return 1
  assert_version_refusal 'Initial release requires an explicit' --package ui --patch || return 1
  run_bumpster --package ui --patch --version-source package-json
  assert_package_release 0.1.1
}

test_version_source_namespaces() {
  create_package_fixture source-namespaces || return 1
  run_bumpster --package ui --patch
  assert_package_release 0.1.1 || return 1
  run_bumpster --minor
  assert_successful_release 0.9.0 || return 1
  assert_contains "$cli_output" 'Confirmed source v0.8.0' || return 1
  assert_contains "$cli_output" 'not participating' || return 1
  run_bumpster --package ui --patch
  assert_equal 0 "$cli_status" "$cli_output" || return 1
  assert_contains "$cli_output" 'Confirmed source ui/v0.1.1' || return 1
  assert_equal 0.9.0 "$(cat "$fixture_worktree/VERSION")" || return 1
  assert_equal 0.1.2 "$(cat "$fixture_worktree/packages/ui/VERSION")" || return 1
  assert_equal 0.1.0 "$(cat "$fixture_worktree/packages/brand/VERSION")"
}

test_version_source_root_choices() {
  local source expected before
  for source in tag:v0.8.0 version-file package-json; do
    create_fixture "source-root-${source//[^a-zA-Z0-9]/-}" || return 1
    enable_package_sync || return 1
    printf '0.8.4' > "$fixture_worktree/VERSION"
    printf '{"version":"0.8.9","nested":{"version":"7.7.7"}}\n' > "$fixture_worktree/package.json"
    git -C "$fixture_worktree" add . || return 1
    git -C "$fixture_worktree" commit -q -m 'Prepare divergent versions' || return 1
    assert_version_refusal 'Version sources disagree' --patch || return 1
    case "$source" in tag:*) expected=0.8.1 ;; version-file) expected=0.8.5 ;; package-json) expected=0.8.10 ;; esac
    before="$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
    run_bumpster --version-source "$source" --patch
    assert_successful_release "$expected" || return 1
    assert_equal "$expected|7.7.7" "$(node -e 'const x=require(process.argv[1]); console.log(x.version+"|"+x.nested.version)' "$fixture_worktree/package.json")" || return 1
    assert_equal 1 "$(git -C "$fixture_worktree" rev-list --count "$before..HEAD")" || return 1
  done
}

test_version_source_package_choices() {
  local source expected
  for source in tag:ui/v0.1.0 version-file package-json; do
    create_package_fixture "source-pkg-${source//[^a-zA-Z0-9]/-}" || return 1
    printf '0.1.4' > "$fixture_worktree/packages/ui/VERSION"
    printf '{"name":"ui","version":"0.1.8"}' > "$fixture_worktree/packages/ui/package.json"
    git -C "$fixture_worktree" add . || return 1
    git -C "$fixture_worktree" commit -q -m 'Prepare divergent package versions' || return 1
    assert_version_refusal 'Version sources disagree' --package ui --patch || return 1
    case "$source" in tag:*) expected=0.1.1 ;; version-file) expected=0.1.5 ;; package-json) expected=0.1.9 ;; esac
    run_bumpster --package ui --version-source "$source" --patch
    assert_equal 0 "$cli_status" "$cli_output" || return 1
    assert_equal "$expected" "$(cat "$fixture_worktree/packages/ui/VERSION")" || return 1
    assert_equal 0.8.0 "$(cat "$fixture_worktree/VERSION")" || return 1
    assert_equal 0.1.0 "$(cat "$fixture_worktree/packages/brand/VERSION")" || return 1
    assert_equal 'packages/ui/VERSION
packages/ui/package.json' "$(git -C "$fixture_worktree" diff-tree --no-commit-id --name-only -r HEAD)" || return 1
  done
}

test_version_source_tag_integrity() {
  create_fixture source-local-only || return 1
  git -C "$fixture_worktree" tag v0.8.1 || return 1
  assert_version_refusal 'Unpublished local release tag' --patch --version-source version-file || return 1
  create_fixture source-retagged || return 1
  git -C "$fixture_worktree" tag -f -a v0.8.0 -m 'Changed annotation only' >/dev/null || return 1
  assert_version_refusal 'Local and origin tag' --patch --version-source version-file || return 1
  create_fixture source-remote-only || return 1
  remove_fixture_tag v0.8.0 || return 1
  git -c user.name=Fixture -c user.email=fixture@example.invalid --git-dir="$fixture_origin" tag -a v0.8.0 main -m 'Remote-only object' || return 1
  run_bumpster --patch
  assert_successful_release 0.8.1 || return 1
  create_fixture source-lightweight || return 1
  remove_fixture_tag v0.8.0 || return 1
  git -C "$fixture_worktree" tag v0.8.0 || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/v0.8.0 || return 1
  run_bumpster --patch
  assert_successful_release 0.8.1
}

test_version_source_tag_files() {
  create_fixture source-tag-file || return 1
  git -C "$fixture_worktree" commit -q --allow-empty -m 'Invalid tagged release' || return 1
  publish_fixture_main || return 1
  git -C "$fixture_worktree" tag -a v0.8.1 -m 'Mismatched version' || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 || return 1
  assert_version_refusal 'disagrees with its version file' --patch --version-source version-file || return 1
  create_fixture source-tag-symlink || return 1
  local blob
  printf '0.8.1' > "$fixture_worktree/VERSION"
  blob="$(printf '0.8.1' | git -C "$fixture_worktree" hash-object -w --stdin)" || return 1
  git -C "$fixture_worktree" update-index --cacheinfo 120000 "$blob" VERSION || return 1
  git -C "$fixture_worktree" commit -q -m 'Historical symlink version' || return 1
  git -C "$fixture_worktree" tag -a v0.8.1 -m 'Invalid historical file type' || return 1
  git -C "$fixture_worktree" add VERSION || return 1
  git -C "$fixture_worktree" commit -q -m 'Restore regular working version' || return 1
  publish_fixture_main || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 || return 1
  assert_version_refusal 'Confirmed version paths must be regular Git files' --patch --version-source version-file || return 1
  create_package_fixture source-tag-manifest || return 1
  printf '0.1.1' > "$fixture_worktree/packages/ui/VERSION"
  printf '{"version":"0.1.2"}' > "$fixture_worktree/packages/ui/package.json"
  git -C "$fixture_worktree" add . || return 1
  git -C "$fixture_worktree" commit -q -m 'Invalid tagged manifest' || return 1
  publish_fixture_main || return 1
  git -C "$fixture_worktree" tag -a ui/v0.1.1 -m 'Invalid manifest' || return 1
  git -C "$fixture_worktree" push -q origin refs/tags/ui/v0.1.1 || return 1
  assert_version_refusal 'Confirmed tag disagrees with its manifest' --package ui --patch --version-source version-file
}

test_version_source_history() {
  local scenario expected
  for scenario in outside duplicate decreasing incomparable; do
    create_fixture "source-history-$scenario" || return 1
    case "$scenario" in
      outside)
        git -C "$fixture_worktree" checkout -q -b other || return 1
        git -C "$fixture_worktree" commit -q --allow-empty -m 'Unmerged release' || return 1
        git -C "$fixture_worktree" tag -a v9.0.0 -m 'Other line' || return 1
        git -C "$fixture_worktree" push -q origin refs/tags/v9.0.0 || return 1
        git -C "$fixture_worktree" checkout -q dev || return 1
        expected='outside the origin release branch history' ;;
      duplicate)
        git -C "$fixture_worktree" tag -a v0.8.1 -m 'Second version at same commit' || return 1
        git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 || return 1
        expected='Multiple release versions point to one commit' ;;
      decreasing)
        git -C "$fixture_worktree" commit -q --allow-empty -m 'Lower tagged version' || return 1
        publish_fixture_main || return 1
        git -C "$fixture_worktree" tag -a v0.7.9 -m 'Decreasing version' || return 1
        git -C "$fixture_worktree" push -q origin refs/tags/v0.7.9 || return 1
        expected='Release versions decrease' ;;
      incomparable)
        git -C "$fixture_worktree" checkout -q -b other || return 1
        git -C "$fixture_worktree" commit -q --allow-empty -m 'Other release' || return 1
        git -C "$fixture_worktree" tag v0.9.0 || return 1
        git -C "$fixture_worktree" checkout -q dev || return 1
        git -C "$fixture_worktree" commit -q --allow-empty -m 'Development release' || return 1
        git -C "$fixture_worktree" tag v0.8.1 || return 1
        git -C "$fixture_worktree" merge -q --no-ff other -m 'Join release lines' || return 1
        publish_fixture_main || return 1
        git -C "$fixture_worktree" push -q origin refs/tags/v0.8.1 refs/tags/v0.9.0 || return 1
        expected='incomparable tag lines' ;;
    esac
    assert_version_refusal "$expected" --patch --version-source version-file || return 1
  done
}

test_version_source_shallow_and_missing_branch() {
  create_fixture source-shallow || return 1
  git clone -q --depth 1 --branch dev "file://$fixture_origin" "$fixture_root/shallow" || return 1
  fixture_worktree="$fixture_root/shallow"
  assert_version_refusal 'requires complete history' --patch --version-source version-file || return 1
  create_fixture source-missing-release-branch || return 1
  git --git-dir="$fixture_origin" update-ref -d refs/heads/main || return 1
  assert_version_refusal 'origin release branch is missing' --patch --version-source version-file
}

test_version_source_parser_and_downgrade() {
  local args
  create_package_fixture source-parser || return 1
  for args in '--version-source' '--version-source invalid --patch' '--version-source version-file --version-source package-json --patch' '--version-source version-file --status' '--version-source version-file --help' '--version-source version-file --version' '--version-source version-file --create-feature' '--version-source version-file --update'; do
    # Intentional splitting of static argument fixtures.
    # shellcheck disable=SC2086
    run_bumpster $args
    [[ "$cli_status" != 0 ]] || { fail "Accepted $args"; return 1; }
  done
  assert_version_refusal 'must name the confirmed tag' --patch --version-source tag:ui/v0.1.0 || return 1
  assert_version_refusal 'must name the confirmed tag' --package ui --patch --version-source tag:v0.8.0 || return 1
  assert_version_refusal 'participating manifest' --patch --version-source package-json || return 1
  printf '0.7.0' > "$fixture_worktree/VERSION"
  git -C "$fixture_worktree" add VERSION || return 1
  git -C "$fixture_worktree" commit -q -m 'Stale development version' || return 1
  assert_version_refusal 'must exceed the last confirmed version' --patch --version-source version-file
}

test_version_source_hook_guards() {
  local scenario before before_refs
  for scenario in dirty index-hidden config tag; do
    create_fixture "source-hook-$scenario" || return 1
    mkdir -p "$fixture_worktree/.bumpster/hooks" || return 1
    printf '/.bumpster/\n' >> "$fixture_worktree/.git/info/exclude"
    case "$scenario" in
      dirty) printf '#!/bin/bash\nprintf 0.8.5 > VERSION\n' > "$fixture_worktree/.bumpster/hooks/pre-bump" ;;
      index-hidden)
        git -C "$fixture_worktree" update-index --assume-unchanged VERSION || return 1
        printf '#!/bin/bash\nprintf 0.8.5 > VERSION\n' > "$fixture_worktree/.bumpster/hooks/pre-bump" ;;
      config) printf '#!/bin/bash\nprintf changed > "$HOME/.bumpsterrc"\n' > "$fixture_worktree/.bumpster/hooks/pre-bump" ;;
      tag) printf '#!/bin/bash\ngit tag v9.9.9\ngit push -q origin refs/tags/v9.9.9\n' > "$fixture_worktree/.bumpster/hooks/pre-bump" ;;
    esac
    chmod +x "$fixture_worktree/.bumpster/hooks/pre-bump" || return 1
    before="$(git -C "$fixture_worktree" rev-parse HEAD)"
    before_refs="$(git --git-dir="$fixture_origin" rev-parse main dev)"
    run_bumpster --patch
    [[ "$cli_status" != 0 ]] || { fail "Accepted hook $scenario"; return 1; }
    assert_equal "$before" "$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
    assert_equal "$before_refs" "$(git --git-dir="$fixture_origin" rev-parse main dev)" || return 1
    [[ "$scenario" != tag ]] || assert_contains "$cli_output" 'tags changed' || return 1
  done
}

test_version_source_staging_failure() {
  local real_mv wrapper old_path
  create_package_fixture source-staging-failure || return 1
  real_mv="$(command -v mv)"
  wrapper="$fixture_root/bin"
  mkdir -p "$wrapper" || return 1
  {
    printf '#!/bin/bash\n'
    printf 'if [[ "$1" == -f && "$3" == */next-1 ]]; then exit 73; fi\n'
    printf 'exec %q "$@"\n' "$real_mv"
  } > "$wrapper/mv"
  chmod +x "$wrapper/mv" || return 1
  old_path="$test_path"; test_path="$wrapper:$test_path"
  assert_version_refusal 'Failed to stage version files safely' --package ui --patch
  local result=$?
  test_path="$old_path"
  [[ "$result" == 0 ]] || return 1
  assert_equal '' "$(git -C "$fixture_worktree" status --porcelain)" || return 1
  assert_equal '' "$(find "$fixture_worktree/packages/ui" -name '.bumpster-release.*' -print)"
}

test_version_source_status_and_node() {
  local old_path real_git wrapper before_refs
  create_package_fixture source-status || return 1
  printf '0.1.4' > "$fixture_worktree/packages/ui/VERSION"
  git -C "$fixture_worktree" add packages/ui/VERSION || return 1
  git -C "$fixture_worktree" commit -q -m 'Divergent status fixture' || return 1
  real_git="$(command -v git)"; wrapper="$fixture_root/bin"
  mkdir -p "$wrapper" || return 1
  {
    printf '#!/bin/bash\n'
    printf 'case "$1" in fetch|ls-remote) printf "Unexpected network access\\n" >&2; exit 88;; esac\n'
    printf 'exec %q "$@"\n' "$real_git"
  } > "$wrapper/git"
  chmod +x "$wrapper/git" || return 1
  old_path="$test_path"; test_path="$wrapper:$test_path"
  before_refs="$(git --git-dir="$fixture_origin" show-ref)"
  run_bumpster --package ui --status
  test_path="$old_path"
  [[ "$cli_status" != 0 ]] || return 1
  assert_contains "$cli_output" 'Version source packages/ui/VERSION: 0.1.4' || return 1
  assert_contains "$cli_output" 'Version source packages/ui/package.json: 0.1.0' || return 1
  assert_contains "$cli_output" 'not verified against origin' || return 1
  assert_not_contains "$cli_output" 'Unexpected network access' || return 1
  assert_equal "$before_refs" "$(git --git-dir="$fixture_origin" show-ref)" || return 1
  create_fixture source-no-node || return 1
  wrapper="$fixture_root/bin"; mkdir -p "$wrapper" || return 1
  printf '#!/bin/bash\nexit 90\n' > "$wrapper/node"
  chmod +x "$wrapper/node" || return 1
  old_path="$test_path"; test_path="$wrapper:$test_path"
  run_bumpster --patch
  test_path="$old_path"
  assert_successful_release 0.8.1
}

test_version_source_structure_and_missing_field() {
  local scenario
  for scenario in invalid-json invalid-version missing-file symlink hardlink missing-field; do
    create_package_fixture "source-structure-$scenario" || return 1
    case "$scenario" in
      invalid-json) printf '{bad}' > "$fixture_worktree/packages/ui/package.json" ;;
      invalid-version) printf '{"version":false}' > "$fixture_worktree/packages/ui/package.json" ;;
      missing-file) git -C "$fixture_worktree" rm -q packages/ui/package.json || return 1 ;;
      symlink)
        node -e 'const fs=require("fs"),path=require("path");const src=path.resolve(process.argv[1]),dst=path.resolve(process.argv[2]);fs.renameSync(src,dst);fs.symlinkSync(dst,src,process.platform === "win32" ? "junction" : "dir");' \
          "$fixture_worktree/packages/ui" "$fixture_root/real-ui" || return 1 ;;
      hardlink)
        rm "$fixture_worktree/packages/ui/VERSION" || return 1
        ln "$fixture_worktree/packages/brand/VERSION" "$fixture_worktree/packages/ui/VERSION" || return 1 ;;
      missing-field) printf '{"nested":{"version":"9.9.9"}}' > "$fixture_worktree/packages/ui/package.json" ;;
    esac
    # Git may follow a Windows junction; leave this link unstaged.
    if [[ "$scenario" != symlink ]]; then git -C "$fixture_worktree" add -A || return 1; fi
    git -C "$fixture_worktree" diff --cached --quiet || git -C "$fixture_worktree" commit -q -m 'Set structural refusal' || return 1
    if [[ "$scenario" == missing-field ]]; then
      assert_version_refusal 'Version sources disagree' --package ui --patch || return 1
      assert_version_refusal 'participating manifest with a version' --package ui --patch --version-source package-json || return 1
      run_bumpster --package ui --patch --version-source version-file
      assert_equal 0 "$cli_status" "$cli_output" || return 1
      assert_equal '0.1.1|9.9.9' "$(node -e 'const x=require(process.argv[1]);console.log(x.version+"|"+x.nested.version)' "$fixture_worktree/packages/ui/package.json")" || return 1
    else
      run_bumpster --package ui --patch --version-source tag:ui/v0.1.0
      [[ "$cli_status" != 0 ]] || { fail "Override accepted $scenario"; return 1; }
      assert_equal 0.1.0 "$(git --git-dir="$fixture_origin" show main:packages/ui/VERSION)" || return 1
      assert_equal '' "$(git --git-dir="$fixture_origin" tag --list ui/v0.1.1)" || return 1
    fi
  done
}

test_version_source_hotfix_override() {
  create_package_fixture source-hotfix || return 1
  git -C "$fixture_worktree" checkout -q -b hotfix/guard main || return 1
  printf fix > "$fixture_worktree/fix.txt"
  git -C "$fixture_worktree" add fix.txt || return 1
  git -C "$fixture_worktree" commit -q -m 'Prepare package hotfix' || return 1
  run_bumpster --package ui --hotfix --version-source tag:ui/v0.1.0
  assert_package_release 0.1.1 || return 1
  create_package_fixture source-hotfix-file || return 1
  git -C "$fixture_worktree" checkout -q -b hotfix/guard main || return 1
  printf '0.1.4' > "$fixture_worktree/packages/ui/VERSION"
  git -C "$fixture_worktree" add packages/ui/VERSION || return 1
  git -C "$fixture_worktree" commit -q -m 'Divergent hotfix version' || return 1
  assert_version_refusal "Hotfix branch VERSION must match" --package ui --hotfix --version-source tag:ui/v0.1.0 || return 1
  create_fixture source-hotfix-branch || return 1
  assert_version_refusal "Hotfix releases must be run from a 'hotfix/" --hotfix --version-source tag:v0.8.0
}

test_version_source_preserves_concurrent_edits() {
  local real_mv wrapper old_path before
  create_package_fixture source-concurrent-write || return 1
  real_mv="$(command -v mv)"; wrapper="$fixture_root/bin"
  mkdir -p "$wrapper" || return 1
  {
    printf '#!/bin/bash\n'
    printf 'if [[ "$1" == -f && "$3" == */next-1 ]]; then printf concurrent > packages/ui/VERSION; exit 73; fi\n'
    printf 'exec %q "$@"\n' "$real_mv"
  } > "$wrapper/mv"
  chmod +x "$wrapper/mv" || return 1
  before="$(git -C "$fixture_worktree" rev-parse HEAD)"
  old_path="$test_path"; test_path="$wrapper:$test_path"
  run_bumpster --package ui --patch
  test_path="$old_path"
  [[ "$cli_status" != 0 ]] || return 1
  assert_contains "$cli_output" 'backups preserved' || return 1
  assert_equal concurrent "$(cat "$fixture_worktree/packages/ui/VERSION")" || return 1
  assert_equal "$before" "$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  assert_equal 0.1.0 "$(node -p 'require(process.argv[1]).version' "$fixture_worktree/packages/ui/package.json")"
}

test_version_source_index_failure() {
  local real_git wrapper old_path result
  create_package_fixture source-index-failure || return 1
  real_git="$(command -v git)"; wrapper="$fixture_root/bin"
  mkdir -p "$wrapper" || return 1
  {
    printf '#!/bin/bash\n'
    printf 'if [[ "$1" == --literal-pathspecs && "$2" == add ]]; then\n'
    printf '  %q "$@" || exit $?\n  exit 74\nfi\n' "$real_git"
    printf 'exec %q "$@"\n' "$real_git"
  } > "$wrapper/git"
  chmod +x "$wrapper/git" || return 1
  old_path="$test_path"; test_path="$wrapper:$test_path"
  assert_version_refusal 'Failed to stage version files safely' --package ui --patch
  result=$?; test_path="$old_path"
  [[ "$result" == 0 ]] || return 1
  assert_equal '' "$(git -C "$fixture_worktree" status --porcelain)"
}

test_version_source_index_flags_and_filters() {
  local scenario
  for scenario in hidden filter; do
    create_fixture "source-index-$scenario" || return 1
    if [[ "$scenario" == hidden ]]; then
      git -C "$fixture_worktree" update-index --assume-unchanged VERSION || return 1
    else
      printf 'VERSION filter=version-fixture\n' > "$fixture_worktree/.gitattributes"
      git -C "$fixture_worktree" config filter.version-fixture.clean 'printf 0.8.0' || return 1
      git -C "$fixture_worktree" add .gitattributes || return 1
      git -C "$fixture_worktree" commit -q -m 'Set a version-changing clean filter' || return 1
    fi
    assert_version_refusal 'Failed to stage version files safely' --patch || return 1
    assert_equal 0.8.0 "$(cat "$fixture_worktree/VERSION")" || return 1
  done
}

test_version_source_foreign_staging() {
  local real_git wrapper old_path before before_refs
  create_package_fixture source-foreign-index || return 1
  real_git="$(command -v git)"; wrapper="$fixture_root/bin"
  mkdir -p "$wrapper" || return 1
  {
    printf '#!/bin/bash\n'
    printf 'if [[ "$1" == --literal-pathspecs && "$2" == add ]]; then\n'
    printf '  %q "$@" || exit $?\n' "$real_git"
    printf '  printf concurrent > README.md\n'
    printf '  %q add README.md || exit $?\n  exit 0\nfi\n' "$real_git"
    printf 'exec %q "$@"\n' "$real_git"
  } > "$wrapper/git"
  chmod +x "$wrapper/git" || return 1
  before="$(git -C "$fixture_worktree" rev-parse HEAD)"
  before_refs="$(git --git-dir="$fixture_origin" show-ref)"
  old_path="$test_path"; test_path="$wrapper:$test_path"
  run_bumpster --package ui --patch
  test_path="$old_path"
  [[ "$cli_status" != 0 ]] || return 1
  assert_contains "$cli_output" 'Index contains changes outside' || return 1
  assert_equal "$before" "$(git -C "$fixture_worktree" rev-parse HEAD)" || return 1
  assert_equal "$before_refs" "$(git --git-dir="$fixture_origin" show-ref)" || return 1
  assert_equal concurrent "$(git -C "$fixture_worktree" show :README.md)"
}

run_version_source_tests() {
  run_test 'concurrent unrelated staging is preserved and never swept into the bump commit' test_version_source_foreign_staging
  run_test 'index skip flags and clean filters cannot silently omit a version update' test_version_source_index_flags_and_filters
  run_test 'failed staging restores only operation-owned index entries' test_version_source_index_failure
  run_test 'status reports all sources without network access; ordinary CLI needs no Node.js' test_version_source_status_and_node
  run_test 'explicit sources cannot bypass unsafe or invalid files; missing fields require consent' test_version_source_structure_and_missing_field
  run_test 'explicit package hotfix retains branch and publication guarantees' test_version_source_hotfix_override
  run_test 'failed staging preserves concurrent edits and reports backup paths' test_version_source_preserves_concurrent_edits
  run_test 'initial CLI and package releases require an explicit source' test_version_source_bootstrap
  run_test 'CLI and package tag namespaces stay independent behind newer HEADs' test_version_source_namespaces
  run_test 'all explicit root version sources reconcile only participating files' test_version_source_root_choices
  run_test 'all explicit package sources preserve root and neighboring versions' test_version_source_package_choices
  run_test 'published tags are authoritative and local tag conflicts are refused' test_version_source_tag_integrity
  run_test 'confirmed tags must match their historical version files and manifests' test_version_source_tag_files
  run_test 'release history rejects foreign lines, duplicates, decreases and ambiguity' test_version_source_history
  run_test 'shallow and incomplete release histories cannot use an override' test_version_source_shallow_and_missing_branch
  run_test 'source modifiers are explicit, release-only and cannot downgrade' test_version_source_parser_and_downgrade
  run_test 'CLI hooks cannot change files, hidden inputs, configuration or origin tags' test_version_source_hook_guards
  run_test 'failed second file replacement restores selected files and leaves refs unchanged' test_version_source_staging_failure
}
