#!/bin/bash

# This command enables strict mode,
# which treats unset variables as errors.
# TODO: make the code comply with the requirement
# set -u

### Begin define variables ###

# Great idea to safely define home by Ben Hoskings, author of "babushka" https://github.com/benhoskings/babushka
home=$(sh -c "echo ~$(whoami)")
# Checks OS type
ostype=$(uname -s)
# Source
from="https://github.com/phoenixweiss/bumpster"
# Destination
to="$home/.bumpster"
# Full path to the "config" file in the ".git" folder
config_path=".git/config"

### End define variables ###

# This function is defined to print an error message
# and exit with a status code of 1.
abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# Function to remove newline character from a string
remove_newline() {
  local string=$1

  # Check if the string contains a newline character
  if [[ $string == *$'\n' ]]; then
      # Remove the newline character from the end of the string
      string=${string%"$'\n'"}
  fi

  # Print the modified string
  printf "$string"
}

# The conditional statement checks if the BASH_VERSION variable is empty,
# indicating that Bash is not available, and calls the abort() function.
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]
then
  abort "Bash is required to run this script."
fi

# The usage() function is defined to display a usage message
# when the script is called with the -h or --help options.
usage() {
  cat ./lib/BUMPSTER_LOGO.ASCII
  cat <<EOS
Bumpster
Usage:  ./bumpster.sh [options]
        -h, --help      Display this message
        -M, --major     Bump major version
        -m, --minor     Bump minor version
        -p, --patch     Bump patch version
EOS
  # The script exits with the status code passed as an argument
  # to the exit command, defaulting to 0 if no argument is provided.
  exit "${1:-0}"
}

# Loop until all arguments are processed.
while [[ $# -gt 0 ]]
do
  case "$1" in
    # If the argument is -h or --help, call the usage function
    -h | --help)    usage
                    ;;
    # If the argument is -M or --major
    -M | --major )  version_type="major"
                    ;;
    # If the argument is -m or --minor
    -m | --minor )  version_type="minor"
                    ;;
    # If the argument is -p or --patch
    -p | --patch )  version_type="patch"
                    ;;
    # If the argument is anything else
    *)
      # Print an error message to stderr
      printf "Unknown option: '$1'\n" >&2
      # Call the usage function with exit code 1
      usage 1
      ;;
  esac
done

# Checking if the git flow repository is initialized
if ! git rev-parse --git-dir >/dev/null 2>&1
then
  abort "Git repository not found. Please initialize git first."
fi

# Checking for uncommitted changes
if [[ -n $(git status --porcelain) ]]
then
  abort "Working tree contains unstaged changes. Aborting."
fi

# Checking if git flow installed
if ! which git-flow >/dev/null 2>&1 || ! git flow version >/dev/null 2>&1
then
  abort "Error: git flow is not installed. Please install it and try again."
fi

# Check if the block [gitflow "branch"] is present in the "config" file
if grep -q "\[gitflow \"branch\"\]" "$config_path"
then
  # Find string 'master = <value>' and assign it to gf_master_branch_name
  gf_master_branch_name=$(grep -oP 'master\s*=\s*\K.*' "$config_path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  # Find string 'develop = <value>' and assign it to gf_develop_branch_name
  gf_develop_branch_name=$(grep -oP 'develop\s*=\s*\K.*' "$config_path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  # Check that the gf_master_branch_name variable is not empty
  if [[ -n $gf_master_branch_name ]]
  then
    echo "Git flow master branch name: $gf_master_branch_name"
  else
    abort "String 'master = <value>' did not found. Please run 'git flow init' first."
  fi

  # Check that the gf_develop_branch_name variable is not empty
  if [[ -n $gf_develop_branch_name ]]
  then
    echo "Git flow develop branch name: $gf_develop_branch_name"
  else
    abort "String 'develop = <value>' did not found. Please run 'git flow init' first."
  fi
else
  abort "Git flow is not initialized. Please run 'git flow init' first."
fi

# Checking the existence of the VERSION file
if [ -f "VERSION" ]
then
  # If flie exists get the current version from the VERSION file
  current_version=$(cat VERSION)
  echo "Current version is $current_version"
else
  # If the file does not exist, create a new one and write version 0.0.1 there
  current_version="0.0.1"
  printf $current_version > VERSION
  echo "The VERSION file is created and filled with the value $current_version"
fi

# If the user has not specified the version type, we ask the user directly
if [ -z "$version_type" ]
then
  read -p "Which version do you want to bump (major/minor/patch)? [patch]: " version_type

  # If the user has not entered anything, we use the patch version by default
  if [ -z "$version_type" ]
  then
    version_type="patch"
  fi
fi

# We change the version in accordance with the selected type
new_version=$(awk -F. '{printf("%d.%d.%d", $1, $2, $3+1)}' <<< $current_version)
case $version_type in
  major) new_version=$(awk -F. '{printf("%d.%d.%d", $1+1, 0, 0)}' <<< $current_version);;
  minor) new_version=$(awk -F. '{printf("%d.%d.%d", $1, $2+1, 0)}' <<< $current_version);;
  patch) new_version=$(awk -F. '{printf("%d.%d.%d", $1, $2, $3+1)}' <<< $current_version);;
esac

# Update the version value in the VERSION file and create a commit
printf $new_version > VERSION
git add VERSION
git commit -m "bump version to $new_version" -m "Automatic version bump to $new_version"

# Create a release branch from the develop branch in accordance with Git Flow
git checkout $gf_develop_branch_name
git flow release start $new_version

# We complete the release branch and create a tag for the new version
GIT_MERGE_AUTOEDIT=no git flow release finish -m "Release $new_version" -m "Automatic release $new_version" $new_version

# Push changes to the server
git push origin $gf_develop_branch_name && git push origin $gf_master_branch_name --tags
