#!/bin/bash

# Variables in this file are intentionally consumed by scripts that source it.
# shellcheck disable=SC2034

# Enable strict mode
set -u

### Begin define variables ###

# Define the home directory of Bumpster
BUMPSTER_HOME="${BUMPSTER_HOME:-$HOME/.bumpster}"

# Global and local config file paths
global_config_file="$HOME/.bumpsterrc"
local_config_file="$(pwd)/.bumpsterrc"

# Define default log file name (can be overridden in .bumpsterrc)
default_log_file="bumpster.log"
log_file="$default_log_file"

# Define the bin directory
bin_dir="$BUMPSTER_HOME/bin"

# Default branch names
default_master_branch="main"
default_develop_branch="dev"
default_before_bump_branch="$default_develop_branch"
default_logging="false"

# Default behavior for feature branch management
delete_feature_branch_after_merge="${DELETE_FEATURE_BRANCH_AFTER_MERGE:-false}"
ask_before_deleting_feature_branch="${ASK_BEFORE_DELETING_FEATURE_BRANCH:-true}"

# Default branch to switch to after bump (default to develop branch)
AFTER_BUMP_BRANCH=${AFTER_BUMP_BRANCH:-"$default_develop_branch"}

# Default branch that must be active before bumping (default to develop branch)
BEFORE_BUMP_BRANCH=${BEFORE_BUMP_BRANCH:-"$default_before_bump_branch"}

# Config variables (overridden by .bumpsterrc if present)
master_branch=""
develop_branch=""
logging_enabled=""

# Latest stable GitHub Release assets
release_download_url="${BUMPSTER_RELEASE_DOWNLOAD_URL:-https://github.com/phoenixweiss/Bumpster/releases/latest/download}"

# Define version file location
local_version_file="$BUMPSTER_HOME/VERSION"

# Define the path to the Bumpster logo file
logo_file="$BUMPSTER_HOME/lib/BUMPSTER_LOGO.ASCII"

### End define variables ###
