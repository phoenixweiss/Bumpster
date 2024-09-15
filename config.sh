#!/bin/bash

# Enable strict mode
set -u

### Begin define variables ###

# Define the home directory of Bumpster
BUMPSTER_HOME="${BUMPSTER_HOME:-$HOME/.bumpster}"

# Global and local config file paths
global_config_file="$HOME/.bumpsterrc"
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
