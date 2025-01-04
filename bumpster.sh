#!/bin/bash

# Source configuration and function files
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/functions.sh"

# Process command-line options
version_type=""
create_local_config=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)              usage ;;
    -v | --version)           echo "Bumpster version: $(display_version)" ; exit 0 ;;
    -M | --major )            version_type="major" ;;
    -m | --minor )            version_type="minor" ;;
    -p | --patch )            version_type="patch" ;;
    -u | --update )           update_bumpster ; exit 0 ;;
    --status )                check_status ; exit 0 ;;
    --create-local-config )   create_local_config="true" ;;
    *)                        printf "Unknown option: '$1'\n" >&2
                              usage 1 ;;
  esac
  shift
done

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

# Ensure VERSION file exists and read the current version
if [ -f "VERSION" ]; then
  current_version=$(cat VERSION)
  log "Current version is $current_version"
else
  current_version="0.0.1"
  printf "$current_version" > VERSION
  log "The VERSION file is created and filled with the value $current_version"
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

# Update the VERSION file and create a commit
printf "$new_version" > VERSION
git add VERSION
git commit -m "bump version to $new_version" -m "Automatic version bump to $new_version"
log "Bumping version to $new_version"

# Handle branch management manually
current_branch=$(git rev-parse --abbrev-ref HEAD)
log "Current branch is $current_branch"

default_dev_branch=${develop_branch:-"develop"}
default_master_branch=${master_branch:-"master"}

# Ensure the current branch is not main or dev
if [[ "$current_branch" != "$default_dev_branch" && "$current_branch" != "$default_master_branch" ]]; then
  log "Merging current branch into $default_dev_branch"
  git checkout "$default_dev_branch"
  git merge "$current_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
  git push origin "$default_dev_branch"
fi

# Create a release from dev to main
log "Creating a release from $default_dev_branch to $default_master_branch"
git checkout "$default_master_branch"
git merge "$default_dev_branch" --no-edit || abort "Merge failed. Please resolve conflicts."
git tag -a "v$new_version" -m "Release $new_version"
git push origin "$default_master_branch" --tags
log "Release $new_version pushed to remote repository"
