#!/bin/bash

# Enable strict mode
set -u

### Begin define variables ###

# Define the home directory of Bumpster
BUMPSTER_HOME="${BUMPSTER_HOME:-$HOME/.bumpster}"

# Global and local config file paths
global_config_file="$BUMPSTER_HOME/.bumpsterrc"
local_config_file="$(pwd)/.bumpsterrc"

# Default values
default_master_branch="master"
default_develop_branch="develop"
default_logging="false"

# Config variables
master_branch=""
develop_branch=""
logging_enabled=""

# Define version file location
version_file="$BUMPSTER_HOME/VERSION"

# Define the path to the Bumpster logo file
logo_file="$BUMPSTER_HOME/lib/BUMPSTER_LOGO.ASCII"

### End define variables ###

# Function to display the version of Bumpster
display_version() {
  if [ -f "$version_file" ]; then
    cat "$version_file"
  else
    echo "Version information not available."
  fi
}

# Function to print an error message and exit with a status code of 1.
abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# Function to log actions if logging is enabled
log() {
  if [[ "$logging_enabled" == "true" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> bumpster.log
  fi
}

# Function to create a config file with the given path and values
create_config() {
  local config_file="$1"
  local master_branch="$2"
  local develop_branch="$3"
  local logging="$4"

  # Use a clean and correctly formatted here-document
  cat > "$config_file" <<EOF
# Bumpster configuration file
# You can change the values here to configure the behavior of Bumpster

# Git master branch (default: master)
GIT_MASTER_BRANCH="$master_branch"

# Git develop branch (default: develop)
GIT_DEVELOP_BRANCH="$develop_branch"

# Enable or disable logging (default: false)
ENABLE_LOGGING="$logging"
EOF
  echo "Configuration file '$config_file' created."
}

# Function to run an interactive session for configuration
interactive_setup() {
  echo "Welcome to Bumpster setup!"
  read -p "Enter the name for the master branch [default: $default_master_branch]: " master_branch_input
  master_branch=${master_branch_input:-$default_master_branch}

  read -p "Enter the name for the develop branch [default: $default_develop_branch]: " develop_branch_input
  develop_branch=${develop_branch_input:-$default_develop_branch}

  read -p "Enable logging? (y/n) [default: no]: " logging_input
  logging_enabled="false"
  if [[ "$logging_input" == "y" || "$logging_input" == "Y" ]]; then
    logging_enabled="true"
  fi

  # Create the global config file based on user input
  create_config "$global_config_file" "$master_branch" "$develop_branch" "$logging_enabled"
}

# Function to load configuration from a config file
load_config() {
  if [ -f "$1" ]; then
    source "$1"
    master_branch="${GIT_MASTER_BRANCH:-$default_master_branch}"
    develop_branch="${GIT_DEVELOP_BRANCH:-$default_develop_branch}"
    logging_enabled="${ENABLE_LOGGING:-$default_logging}"
  fi
}

# Check if either local or global config exists, load the local config first
if [ -f "$local_config_file" ];then
  echo "Using local configuration from '$local_config_file'."
  load_config "$local_config_file"
  elif [ -f "$global_config_file" ]; then
  echo "Using global configuration from '$global_config_file'."
  load_config "$global_config_file"
else
  echo "No configuration file found."
  interactive_setup
fi

# Function to show usage and version information
usage() {
  if [ -f "$logo_file" ]; then
    cat "$logo_file"
  else
    echo "Bumpster"
  fi

  cat <<EOS
Bumpster $(display_version)
Usage:  bumpster [options]
        -h, --help      Display this message
        -M, --major     Bump major version
        -m, --minor     Bump minor version
        -p, --patch     Bump patch version
        --version       Display the current version of Bumpster
EOS
  exit "${1:-0}"
}

# Check command-line options
version_type=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)    usage ;;
    --version)      echo "Bumpster version: $(display_version)"
    exit 0 ;;
    -M | --major )  version_type="major" ;;
    -m | --minor )  version_type="minor" ;;
    -p | --patch )  version_type="patch" ;;
    *)              printf "Unknown option: '$1'\n" >&2
    usage 1 ;;
  esac
  shift
done

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
  gf_master_branch_name=$(grep -oP 'master\s*=\s*\K.*' ".git/config" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  gf_develop_branch_name=$(grep -oP 'develop\s*=\s*\K.*' ".git/config" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

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
