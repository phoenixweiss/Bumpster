#!/bin/bash

export LC_ALL=C.UTF-8

# Source configuration and function files
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/functions.sh"

# Process command-line options
version_type=""
create_local_config=""
create_feature_branch=""
close_feature_branch=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)                    usage ;;
    -v | --version)                 echo "Bumpster version: $(display_version)" ; exit 0 ;;
    -M | --major )                  version_type="major" ;;
    -m | --minor )                  version_type="minor" ;;
    -p | --patch )                  version_type="patch" ;;
    -u | --update )                 update_bumpster ; exit 0 ;;
    -s | --status )                 check_status ; exit 0 ;;
    -l | --create-local-config )    create_local_config="true" ;;
    -f | --create-feature )         create_feature_branch="true" ;;
    -c | --close-feature )          close_feature_branch="true" ;;
    *)                              printf "Unknown option: '%s'\n" "$1" >&2
    usage 1 ;;
  esac
  shift
done

# Preload configuration if branch-management commands were requested
if [[ "$close_feature_branch" == "true" || "$create_feature_branch" == "true" ]]; then
  if [ -f "$local_config_file" ]; then
    load_config "$local_config_file"
  elif [ -f "$global_config_file" ]; then
    load_config "$global_config_file"
  fi
fi

# Close a feature branch if the option was passed
if [[ "$close_feature_branch" == "true" ]]; then
  close_feature
  exit 0
fi

# Create a feature branch if the option was passed
if [[ "$create_feature_branch" == "true" ]]; then
  create_feature
  exit 0
fi

# Create local configuration file if the option was passed
if [[ "$create_local_config" == "true" ]]; then
  create_local_config_file
  exit 0
fi

# Check if either local or global config exists, load the local config first
if [ -f "$local_config_file" ]; then
  log "Using local configuration from '$local_config_file'."
  load_config "$local_config_file"
elif [ -f "$global_config_file" ]; then
  log "Using global configuration from '$global_config_file'."
  load_config "$global_config_file"
else
  log "No configuration file found."
  log "Running initial setup..."
  interactive_setup
fi

# Ensure Bash is available
if [ -z "${BASH_VERSION:-}" ]; then
  abort "Bash is required to run this script."
fi

# Ensure necessary commands are available
required_commands=(git)
for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    abort "Error: $cmd is not installed. Please install it and try again."
  fi
done

# Ensure the script is run in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  abort "Git repository not found. Please initialize git first."
fi

# Ensure there are no uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
  abort "Working tree contains unstaged changes. Aborting."
fi

# Ensure the configured before-bump branch exists and is checked out
required_before_branch="${before_bump_branch:-$default_before_bump_branch}"
if [[ -z "$required_before_branch" ]]; then
  required_before_branch="$default_before_bump_branch"
fi
if ! git show-ref --verify --quiet "refs/heads/$required_before_branch"; then
  abort "Configured BEFORE_BUMP_BRANCH '$required_before_branch' does not exist. Please create it or update your configuration."
fi
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "$required_before_branch" ]]; then
  abort "Version bumps must be run from '$required_before_branch' (current branch: '$current_branch')."
fi

# Resolve release branches before calculating and validating the release plan
default_dev_branch=${develop_branch:-"$default_develop_branch"}
default_master_branch=${master_branch:-"$default_master_branch"}

export default_dev_branch
export default_master_branch

# Ensure VERSION contains a strict semantic version
if [ -f "VERSION" ]; then
  current_version=$(cat VERSION) || abort "Failed to read the VERSION file."
  if [[ ! "$current_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    abort "VERSION must contain MAJOR.MINOR.PATCH with no prefix, suffix, or leading zeros."
  fi
  log "Current version is $current_version"
else
  abort "VERSION file not found. Create it with a semantic version such as 0.1.0 before releasing."
fi

# Prompt for version type if not provided
if [ -z "$version_type" ]; then
  read -r -p "Which version do you want to bump (major/minor/patch)? [patch]: " version_type
  version_type=${version_type:-patch}
fi

# Validate version type
if [[ "$version_type" != "major" && "$version_type" != "minor" && "$version_type" != "patch" ]]; then
  abort "Invalid version type. Please choose between 'major', 'minor', or 'patch'."
fi

# Parse the current version and bump it
IFS='.' read -r major minor patch <<< "$current_version"
case $version_type in
  major) ((major++)); minor=0; patch=0 ;;
  minor) ((minor++)); patch=0 ;;
  patch) ((patch++)) ;;
esac
new_version="$major.$minor.$patch"

# Check if the new version is different from the current one
if [[ "$current_version" == "$new_version" ]]; then
  abort "New version is the same as the current version."
fi

# Validate package.json before hooks or the first local release mutation
if [[ "${sync_with_package_json}" == "true" && -f "package.json" ]]; then
  validate_package_json_for_sync "package.json" ||
    abort "package.json cannot be synchronized safely."
fi

# Validate local and remote release state before running hooks or changing files
preflight_release "$new_version" "$default_dev_branch" "$default_master_branch"

# Expose versions to hooks and run pre-bump hook
export BUMPSTER_PREV_VERSION="$current_version"
export BUMPSTER_NEW_VERSION="$new_version"
run_hook "pre-bump"

# Preserve exact release state for diagnostics after the first local mutation
release_diagnostics_active="true"
release_published="false"
release_stage="updating VERSION"
release_tag_name="v$new_version"
release_develop_branch="$default_dev_branch"
release_master_branch="$default_master_branch"
trap 'release_exit_handler "$?"' EXIT

# Update the VERSION file and create a commit
printf '%s' "$new_version" > VERSION ||
  abort "Failed to write version $new_version to VERSION."
git add VERSION || abort "Failed to stage VERSION."

# Synchronize version with package.json if enabled
if [[ "${sync_with_package_json}" == "true" ]]; then
  release_stage="synchronizing package.json"
  if [ -f "package.json" ]; then
    log "Synchronizing version with package.json."
    update_package_json_version "package.json" "$new_version" ||
      abort "Failed to update the root package.json version safely."
    git add package.json || abort "Failed to stage package.json."
    log "Updated version in package.json to ${new_version}."
  else
    log "package.json not found. Skipping synchronization."
  fi
fi

# Commit the changes
release_stage="creating the version commit"
git commit -m "bump version to $new_version" -m "Automatic version bump to $new_version" ||
  abort "Failed to create the version commit."
log "Bumping version to $new_version"

# Handle branch management manually
current_branch=$(git rev-parse --abbrev-ref HEAD)
log "Current branch is $current_branch"

# Determine the branch to switch to after bump
after_bump_branch=${AFTER_BUMP_BRANCH:-$default_develop_branch}

# Ensure the branch exists
if ! git show-ref --verify --quiet "refs/heads/$after_bump_branch"; then
  log "Branch '$after_bump_branch' does not exist. Falling back to development branch '$default_develop_branch'."
  after_bump_branch="$default_develop_branch"
fi

# Switch to the after bump branch
release_stage="switching to the after-bump branch"
log "Switching to branch '$after_bump_branch'."
git checkout "$after_bump_branch" || abort "Failed to switch to branch '$after_bump_branch'."

release_stage="preparing the development branch"
log "Ensuring branch '$default_dev_branch' exists before merging."
check_or_create_branch "$default_dev_branch"
log "Switching to branch '$default_dev_branch' for merging."

# Merge current branch into dev
if [[ "$current_branch" != "$default_dev_branch" && "$current_branch" != "$default_master_branch" ]]; then
  release_stage="merging into the development branch"
  log "Merging current branch '$current_branch' into '$default_dev_branch'."
  git merge "$current_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
fi

# Create a release from dev to main

release_stage="preparing the main branch"
log "Ensuring branch '$default_master_branch' exists before releasing."
check_or_create_branch "$default_master_branch"
log "Switching to branch '$default_master_branch' for releasing."

release_stage="merging the development branch into main"
log "Creating a release from '$default_dev_branch' to '$default_master_branch'."
git merge "$default_dev_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
release_stage="creating the release tag"
git tag -a "v$new_version" -m "Release $new_version" ||
  abort "Failed to create release tag 'v$new_version'."

# Publish both release branches and the tag as one remote transaction
release_stage="atomic publication"
log "Publishing '$default_dev_branch', '$default_master_branch', and tag 'v$new_version' atomically."
git push --atomic origin \
  "$default_dev_branch" \
  "$default_master_branch" \
  "refs/tags/v$new_version" ||
  abort "Failed to publish the release atomically. Verify local and remote refs before recovery."

release_published="true"
release_stage="configuring branch upstreams"
git branch --set-upstream-to="origin/$default_dev_branch" "$default_dev_branch" >/dev/null 2>&1 ||
  log "Could not configure upstream for '$default_dev_branch'." "WARN"
git branch --set-upstream-to="origin/$default_master_branch" "$default_master_branch" >/dev/null 2>&1 ||
  log "Could not configure upstream for '$default_master_branch'." "WARN"
log "Release branches and tag published successfully."

# Switch to after bump branch if specified
if [[ -n "$after_bump_branch" ]]; then
  release_stage="switching to the after-bump branch after publication"
  log "Switching to branch '$after_bump_branch' after bumping version."
  if git show-ref --verify --quiet "refs/heads/$after_bump_branch"; then
    git checkout "$after_bump_branch" || abort "Failed to switch to branch '$after_bump_branch'."
  else
    log "Branch '$after_bump_branch' does not exist. Falling back to '$default_master_branch'."
    git checkout "$default_master_branch" || abort "Failed to switch to branch '$default_master_branch'."
  fi
fi

# Run post-bump hook if available
release_stage="post-bump hook"
run_hook "post-bump"

release_diagnostics_active="false"
trap - EXIT
