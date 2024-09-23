#!/bin/bash

# Function to log actions if logging is enabled, otherwise print to STDOUT
log() {
  local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"

  # Always print to STDOUT
  echo "$message"

  # If logging is enabled, write to the log file as well
  if [[ "$logging_enabled" == "true" ]]; then
    echo "$message" >> bumpster.log
  fi
}

# Function to display the version of Bumpster
display_version() {
  if [ -f "$local_version_file" ]; then
    cat "$local_version_file"
  else
    echo "Version information not available."
  fi
}

# Function to print an error message and exit with a status code 1
abort() {
  log "$@"
  exit 1
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
  log "Configuration file '$config_file' created."
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
    log "Local configuration file already exists at $local_config_file."
  else
    interactive_setup "$local_config_file"
    log "Local configuration file created at $local_config_file."
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

# Function to perform post-installation steps
post_install() {

  # Log the post-installation process
  log "Performing post-installation steps"

  # Make the main script executable
  log "Setting executable permissions for bumpster.sh"
  chmod +x "$BUMPSTER_HOME/bumpster.sh"

  # Check if chmod was successful
  if [ $? -ne 0 ]; then
    log "Failed to set executable permissions for bumpster.sh" >&2
  else
    log "Executable permissions set for bumpster.sh"
  fi

  # Create the bin directory if it doesn't exist
  mkdir -p "$bin_dir"

  # Create the wrapper script in bin_dir
  cat > "$bin_dir/bumpster" <<EOF
#!/bin/bash
"\$HOME/.bumpster/bumpster.sh" "\$@"
EOF

  # Make the wrapper script executable
  chmod +x "$bin_dir/bumpster"
}

# Function to update Bumpster to the latest version
update_bumpster() {
  local remote_version
  local local_version

  # Check if VERSION file exists
  if [ -f "$local_version_file" ]; then
    local_version=$(cat "$local_version_file")
  else
    log "Local version information not available."
    local_version="0.0.0"
  fi

  # Fetch the remote version
  remote_version=$(curl -s "$remote_version_file")

  # Compare versions
  if [ "$local_version" != "$remote_version" ]; then
    log "Updating Bumpster from version $local_version to $remote_version..."

    # Create a backup
    local backup_dir="$BUMPSTER_HOME.backup.$local_version"
    cp -r "$BUMPSTER_HOME" "$backup_dir"
    log "Backup of the current version created at $backup_dir."

    # Download and extract the latest version to a temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    curl -L -# "$version_url" | tar -zxf - --strip-components 1 -C "$temp_dir"

    # Replace the old files with the new ones
    rm -rf "$BUMPSTER_HOME"
    mv "$temp_dir" "$BUMPSTER_HOME"

    # Perform post-installation steps
    post_install

    log "Bumpster has been updated to version $remote_version."
  else
    log "You are already using the latest version of Bumpster ($local_version)."
  fi
}

# Function to show usage and version information
usage() {
  if [ -f "$logo_file" ]; then
    cat "$logo_file"
  else
    echo "Bumpster"
  fi

  # Display the local version
  local_version=$(display_version)

  # Fetch the remote version
  remote_version=$(curl -s --max-time 2 "$remote_version_file")

  # Check if the remote version was successfully fetched
  if [ -n "$remote_version" ]; then
    if [ "$local_version" != "$remote_version" ]; then
      version_info="$local_version (a newer version $remote_version is available)"
    else
      version_info="$local_version"
    fi
  else
    version_info="$local_version"
  fi

  cat <<EOS
Bumpster $version_info
Usage:  bumpster [options]
        -h, --help               Display this message
        -M, --major              Bump major version
        -m, --minor              Bump minor version
        -p, --patch              Bump patch version
        -u, --update             Update Bumpster to the latest version
        -v, --version            Display the current version of Bumpster
        --create-local-config    Create a local configuration file in the current directory
EOS
  exit "${1:-0}"
}
