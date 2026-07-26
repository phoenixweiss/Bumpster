#!/usr/bin/env bash

set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s TAG EXPECTED_COMMIT MAIN_BRANCH\n' "${0##*/}" >&2
  exit 2
fi

tag_name="$1"
expected_commit="$2"
main_branch="$3"

if [[ ! "$tag_name" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Release tag must use the vMAJOR.MINOR.PATCH format: %s\n' "$tag_name" >&2
  exit 1
fi

if ! git check-ref-format --branch "$main_branch" >/dev/null 2>&1; then
  printf 'Invalid main branch name: %s\n' "$main_branch" >&2
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Release validation requires a Git repository.\n' >&2
  exit 1
fi

version="${tag_name#v}"
if [[ ! -f VERSION ]]; then
  printf 'VERSION file not found.\n' >&2
  exit 1
fi

file_version="$(tr -d '[:space:]' < VERSION)"
if [[ "$file_version" != "$version" ]]; then
  printf 'Tag %s does not match VERSION (%s).\n' "$tag_name" "$file_version" >&2
  exit 1
fi

if ! tag_type="$(git cat-file -t "refs/tags/$tag_name" 2>/dev/null)"; then
  printf 'Release tag %s does not exist locally.\n' "$tag_name" >&2
  exit 1
fi
if [[ "$tag_type" != "tag" ]]; then
  printf 'Release tag %s must be annotated.\n' "$tag_name" >&2
  exit 1
fi

tag_commit="$(git rev-list -n 1 "$tag_name")" || exit 1
if [[ "$tag_commit" != "$expected_commit" ]]; then
  printf 'Tag %s resolves to %s instead of workflow commit %s.\n' \
    "$tag_name" "$tag_commit" "$expected_commit" >&2
  exit 1
fi

commit_subject="$(git show -s --format=%s "$tag_commit")" || exit 1
if [[ "$commit_subject" != "bump version to $version" ]]; then
  printf 'Release commit has an unexpected subject: %s\n' "$commit_subject" >&2
  exit 1
fi

git fetch --quiet --no-tags origin \
  "+refs/heads/$main_branch:refs/remotes/origin/$main_branch" ||
  {
    printf 'Could not fetch origin/%s.\n' "$main_branch" >&2
    exit 1
  }

remote_main="$(git rev-parse "refs/remotes/origin/$main_branch")" || exit 1
if [[ "$remote_main" != "$tag_commit" ]]; then
  printf 'Tag %s is not the current origin/%s commit.\n' "$tag_name" "$main_branch" >&2
  exit 1
fi

if ! git ls-remote --exit-code --tags origin "refs/tags/$tag_name" >/dev/null 2>&1; then
  printf 'Tag %s is not available on origin.\n' "$tag_name" >&2
  exit 1
fi

if ! "$project_root/scripts/release-notes.sh" "$version" >/dev/null; then
  exit 1
fi

printf '%s\n' "$version"
