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
    *)                              printf "Unknown option: '$1'\n" >&2
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
for cmd in git; do
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

# Ensure VERSION file exists and read the current version
if [ -f "VERSION" ]; then
  current_version=$(cat VERSION)
  log "Current version is $current_version"
else
  current_version="0.0.0"
  printf "$current_version" > VERSION
  log "The VERSION file is created and filled with the value $current_version"
  log "Initialization complete with version $current_version."
  git add VERSION
  git commit -m "Initialize versioning with $current_version"
  log "Version file committed to repository."
fi

# Prompt for version type if not provided
if [ -z "$version_type" ]; then
  read -p "Which version do you want to bump (major/minor/patch)? [patch]: " version_type
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

# Expose versions to hooks and run pre-bump hook
export BUMPSTER_PREV_VERSION="$current_version"
export BUMPSTER_NEW_VERSION="$new_version"
run_hook "pre-bump"

# Update the VERSION file and create a commit
printf "$new_version" > VERSION
git add VERSION

# Synchronize version with package.json if enabled
if [[ "${sync_with_package_json}" == "true" ]]; then
  if [ -f "package.json" ]; then
    log "Synchronizing version with package.json."
    # Update version in package.json
    while IFS= read -r line; do
      if [[ "$line" =~ \"version\": ]]; then
        echo "  \"version\": \"${new_version}\"," >> package.tmp
      else
        echo "$line" >> package.tmp
      fi
    done < package.json
    mv package.tmp package.json
    git add package.json
    log "Updated version in package.json to ${new_version}."
  else
    log "package.json not found. Skipping synchronization."
  fi
fi

# Commit the changes
git commit -m "bump version to $new_version" -m "Automatic version bump to $new_version"
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
log "Switching to branch '$after_bump_branch'."
git checkout "$after_bump_branch" || abort "Failed to switch to branch '$after_bump_branch'."

default_dev_branch=${develop_branch:-"dev"}
default_master_branch=${master_branch:-"main"}

# Export variables if needed
export default_dev_branch
export default_master_branch

log "Ensuring branch '$default_dev_branch' exists before merging."
check_or_create_branch "$default_dev_branch"
log "Switching to branch '$default_dev_branch' for merging."

# Merge current branch into dev
if [[ "$current_branch" != "$default_dev_branch" && "$current_branch" != "$default_master_branch" ]]; then
  log "Merging current branch '$current_branch' into '$default_dev_branch'."
  git merge "$current_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
  git push origin "$default_dev_branch"
fi

# Create a release from dev to main

log "Ensuring branch '$default_master_branch' exists before releasing."
check_or_create_branch "$default_master_branch"
log "Switching to branch '$default_master_branch' for releasing."

log "Creating a release from '$default_dev_branch' to '$default_master_branch'."
git merge "$default_dev_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
git tag -a "v$new_version" -m "Release $new_version"

# Push the dev branch
log "Pushing changes to development branch '$default_dev_branch'."
git push origin "$default_dev_branch" || abort "Failed to push changes to remote branch '$default_dev_branch'."
log "Development branch '$default_dev_branch' pushed to remote repository."

# Push the main branch
log "Pushing changes to main branch '$default_master_branch'."
git push origin "$default_master_branch" --tags || abort "Failed to push changes to remote branch '$default_master_branch'."
log "Main branch '$default_master_branch' pushed to remote repository."

# Switch to after bump branch if specified
if [[ -n "$after_bump_branch" ]]; then
  log "Switching to branch '$after_bump_branch' after bumping version."
  if git show-ref --verify --quiet "refs/heads/$after_bump_branch"; then
    git checkout "$after_bump_branch" || abort "Failed to switch to branch '$after_bump_branch'."
  else
    log "Branch '$after_bump_branch' does not exist. Falling back to '$default_master_branch'."
    git checkout "$default_master_branch" || abort "Failed to switch to branch '$default_master_branch'."
  fi
fi

# Run post-bump hook if available
run_hook "post-bump"
