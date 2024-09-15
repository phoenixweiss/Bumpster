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
  echo "Using local configuration from '$local_config_file'."
  load_config "$local_config_file"
elif [ -f "$global_config_file" ]; then
  echo "Using global configuration from '$global_config_file'."
  load_config "$global_config_file"
else
  echo "No configuration file found."
  echo "Running initial setup..."
  interactive_setup
fi

# Ensure Bash is available
if [ -z "${BASH_VERSION:-}" ]; then
  abort "Bash is required to run this script."
fi

# Ensure necessary commands are available
for cmd in git git-flow; do
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

# Check if git flow is initialized and get branch names
if grep -q "\[gitflow \"branch\"\]" ".git/config"; then
  gf_master_branch_name=$(git config gitflow.branch.master)
  gf_develop_branch_name=$(git config gitflow.branch.develop)

  # Use default names if not found
  gf_master_branch_name=${gf_master_branch_name:-$master_branch}
  gf_develop_branch_name=${gf_develop_branch_name:-$develop_branch}
else
  abort "Git flow is not initialized. Please run 'git flow init' first."
fi

# Ensure VERSION file exists and read the current version
if [ -f "VERSION" ]; then
  current_version=$(cat VERSION)
  echo "Current version is $current_version"
else
  current_version="0.0.1"
  printf "$current_version" > VERSION
  echo "The VERSION file is created and filled with the value $current_version"
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

# Create a release branch and finalize the release with git flow
git checkout "$gf_develop_branch_name"
git flow release start "$new_version"
GIT_MERGE_AUTOEDIT=no git flow release finish -m "Release $new_version" -m "Automatic release $new_version" "$new_version"

# Push changes to the repository
git push origin "$gf_develop_branch_name" && git push origin "$gf_master_branch_name" --tags
log "Release $new_version pushed to remote repository"
