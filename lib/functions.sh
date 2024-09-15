#!/bin/bash

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
  local config_file="${1:-$global_config_file}"
  echo "Welcome to Bumpster setup!"
  read -p "Enter the name for the master branch [default: $default_master_branch]: " master_branch_input
  master_branch=${master_branch_input:-$default_master_branch}

  read -p "Enter the name for the develop branch [default: $default_develop_branch]: " develop_branch_input
  develop_branch=${develop_branch_input:-$default_develop_branch}

  read -p "Enable logging? (y/n) [default: no]: " logging_input
  logging_enabled="false"
  if [[ "$logging_input" =~ ^(y|Y|yes|Yes)$ ]]; then
    logging_enabled="true"
  fi

  # Create the config file based on user input
  create_config "$config_file" "$master_branch" "$develop_branch" "$logging_enabled"
}

# Function to create a local config file in the current directory
create_local_config_file() {
  local current_dir=$(pwd)
  local local_config_file="$current_dir/.bumpsterrc"

  if [ -f "$local_config_file" ]; then
    echo "Local configuration file already exists at $local_config_file."
  else
    interactive_setup "$local_config_file"
    echo "Local configuration file created at $local_config_file."
  fi
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
        -h, --help               Display this message
        -M, --major              Bump major version
        -m, --minor              Bump minor version
        -p, --patch              Bump patch version
        -v, --version            Display the current version of Bumpster
        --create-local-config    Create a local configuration file in the current directory
EOS
  exit "${1:-0}"
}
