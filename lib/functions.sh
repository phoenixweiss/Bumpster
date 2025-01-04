#!/bin/bash

# Function to log actions if logging is enabled, otherwise print to STDOUT
log() {
  local message="$1"

  # Print message to STDOUT without date/time
  echo "$message"

  # If logging is enabled, write message to log file with date/time
  if [[ "$logging_enabled" == "true" ]]; then
    local timestamped_message="$(date '+%Y-%m-%d %H:%M:%S') - $message"
    echo "$timestamped_message" >> "$log_file"
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
  local log_file="${5:-$default_log_file}"
  local delete_feature="${6:-false}"
  local ask_before_deleting="${7:-true}"

  # Use a clean and correctly formatted here-document
  cat > "$config_file" <<EOF
# Bumpster configuration file
# You can change the values here to configure the behavior of Bumpster

# Git master branch (default: main)
GIT_MASTER_BRANCH="$master_branch"

# Git develop branch (default: dev)
GIT_DEVELOP_BRANCH="$develop_branch"

# Enable or disable logging (default: false)
ENABLE_LOGGING="$logging"

# Path to the log file (default: bumpster.log)
LOG_FILE="$log_file"

# Automatically delete feature branches after merge (default: false)
DELETE_FEATURE_BRANCH_AFTER_MERGE="$delete_feature"

# Ask before deleting feature branches (default: true)
ASK_BEFORE_DELETING_FEATURE_BRANCH="$ask_before_deleting"
EOF
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

  read -p "Enter the log file path [default: $default_log_file]: " log_file_input
  log_file=${log_file_input:-$default_log_file}

  read -p "Automatically delete feature branches after merge? (y/n) [default: no]: " delete_feature_input
  delete_feature="false"
  if [[ "$delete_feature_input" =~ ^(y|Y|yes|Yes)$ ]]; then
    delete_feature="true"
  fi

  read -p "Ask before deleting feature branches? (y/n) [default: yes]: " ask_before_deleting_input
  ask_before_deleting="true"
  if [[ "$ask_before_deleting_input" =~ ^(n|N|no|No)$ ]]; then
    ask_before_deleting="false"
  fi

  # Create the config file based on user input
  create_config "$config_file" "$master_branch" "$develop_branch" "$logging_enabled" "$log_file" "$delete_feature" "$ask_before_deleting"
}

# Function to create a local config file in the current directory
create_local_config_file() {
  local current_dir=$(pwd)
  local local_config_file="$current_dir/.bumpsterrc"

  if [ -f "$local_config_file" ]; then
    log "Local configuration file already exists at: $local_config_file"
  else
    interactive_setup "$local_config_file"
    log "Local configuration file successfully created at: $local_config_file"
  fi
}

# Function to load configuration from a config file
load_config() {
  if [ -f "$1" ]; then
    source "$1"
    master_branch="${GIT_MASTER_BRANCH:-$default_master_branch}"
    develop_branch="${GIT_DEVELOP_BRANCH:-$default_develop_branch}"
    logging_enabled="${ENABLE_LOGGING:-$default_logging}"
    log_file="${LOG_FILE:-$default_log_file}"
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
    log "Failed to set executable permissions for bumpster.sh"
    echo "Please manually set the execution permissions:"
    echo "  chmod +x $BUMPSTER_HOME/bumpster.sh"
  else
    log "Executable permissions successfully set for bumpster.sh"
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
    log "Backup created at $backup_dir."

    # Download and extract the latest version to a temporary directory
    local temp_dir=$(mktemp -d)
    curl -L -# "$version_url" | tar -zxf - --strip-components 1 -C "$temp_dir"

    # Replace the old files with the new ones
    rm -rf "$BUMPSTER_HOME"
    mv "$temp_dir" "$BUMPSTER_HOME"

    # Perform post-installation steps
    post_install

    log "Bumpster updated to version $remote_version."
  else
    log "You are already using the latest version ($local_version)."
  fi
}

# Function to check repository status
check_status() {
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  log "Current branch: $current_branch"

  if [[ "$current_branch" == "${develop_branch:-develop}" ]]; then
    log "You are on the development branch. Ready for new features."
  elif [[ "$current_branch" == "${master_branch:-master}" ]]; then
    log "You are on the master branch. Only releases should be here."
  else
    log "You are on a feature branch. Merge your changes into the development branch when ready."
  fi

  log "Uncommitted changes: $(git status --porcelain | wc -l)"
  log "Unpushed commits: $(git cherry -v | wc -l)"
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

  # Check if the remote version was successfully fetched and compare
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
        -h, --help                   Show this help message
        -M, --major                  Bump major version
        -m, --minor                  Bump minor version
        -p, --patch                  Bump patch version
        -u, --update                 Update Bumpster to the latest version
        -v, --version                Show current version
        -s, --status                 Show repository status
        -l, --create-local-config    Create a local configuration file
        -f, --create-feature         Create a new feature branch
        -c, --close-feature          Close the current feature branch

Configuration options:
  GIT_MASTER_BRANCH                   Name of the master branch (default: main)
  GIT_DEVELOP_BRANCH                  Name of the development branch (default: dev)
  ENABLE_LOGGING                      Enable or disable logging (default: false)
  LOG_FILE                            Path to the log file (default: bumpster.log)
  DELETE_FEATURE_BRANCH_AFTER_MERGE   Automatically delete feature branches after merge (default: false)
  ASK_BEFORE_DELETING_FEATURE_BRANCH  Ask before deleting feature branches (default: true)
EOS
  exit "${1:-0}"
}

# Function to check if a branch exists locally or remotely, and create it if necessary
check_or_create_branch() {
  local branch_name="$1"

  # Check if the branch exists locally
  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    log "Branch '$branch_name' does not exist locally. Creating it."
    git checkout -b "$branch_name" || abort "Failed to create branch '$branch_name'."
    log "Branch '$branch_name' successfully created locally."

    # Check if the branch needs to be pushed remotely
    if ! git ls-remote --exit-code origin "$branch_name" &>/dev/null; then
      log "Branch '$branch_name' does not exist remotely. Pushing it."
      git push -u origin "$branch_name" || log "Failed to push branch '$branch_name' to remote."
      log "Branch '$branch_name' successfully pushed to remote."
    fi
  else
    log "Branch '$branch_name' already exists locally."

    # Ensure the branch is tracking the remote one
    git checkout "$branch_name" || abort "Failed to switch to branch '$branch_name'."
    if ! git ls-remote --exit-code origin "$branch_name" &>/dev/null; then
      log "Branch '$branch_name' exists locally but not remotely. Pushing it."
      git push -u origin "$branch_name"
    fi
  fi
}

# Function to create a feature branch from the current dev branch
create_feature() {
  # Ensure the default_dev_branch is set
  local dev_branch=${default_dev_branch:-"dev"}

  # Ensure the current branch is dev
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" != "$dev_branch" ]]; then
    abort "You are not on the development branch ('$dev_branch'). Switch to it before creating a feature branch."
  fi

  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$current_branch" ]]; then
    abort "Current branch mismatch. Expected '$dev_branch'."
  fi

  # Prompt for the feature branch name
  local feature_branch_name
  while true; do
    read -p "Enter the name for the new feature branch: " feature_branch_name
    # Validate the branch name
    if [[ -z "$feature_branch_name" ]]; then
      echo "Branch name cannot be empty. Please try again."
    elif [[ ! "$feature_branch_name" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
      echo "Invalid branch name. Only alphanumeric characters, '/', '_', and '-' are allowed."
    else
      break
    fi
  done

  # Ensure the branch does not already exist
  if git show-ref --verify --quiet "refs/heads/$feature_branch_name"; then
    echo "Branch '$feature_branch_name' already exists. Please choose a different name."
    exit 1
  fi

  # Create and switch to the feature branch
  log "Creating feature branch '$feature_branch_name' from '$current_branch'."
  git checkout -b "$feature_branch_name" || abort "Failed to create branch '$feature_branch_name'."
  log "Feature branch '$feature_branch_name' created and checked out."
}

# Function to close the current feature branch
close_feature() {
  # Ensure the default_dev_branch is set
  local dev_branch=${default_dev_branch:-"dev"}

  # Check for uncommitted changes
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ -n $(git status --porcelain) ]]; then
    log "You have uncommitted changes in your working directory."
    read -p "Do you want to stash these changes before proceeding? (y/n): " stash_response
    if [[ "$stash_response" =~ ^(y|Y|yes|Yes)$ ]]; then
      git stash push -m "Auto-stash before closing feature branch" || abort "Failed to stash changes."
      log "Uncommitted changes stashed successfully."
    else
      log "Proceeding with uncommitted changes."
    fi
  fi

  # Ensure the current branch is a feature branch
  if [[ "$current_branch" == "$dev_branch" || "$current_branch" == "$default_master_branch" ]]; then
    abort "Cannot close a feature branch from '$current_branch'. Please switch to a feature branch."
  fi

  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$current_branch" ]]; then
    abort "Current branch mismatch. Expected '$current_branch'."
  fi


  # Switch to the development branch
  log "Switching to development branch '$dev_branch'."
  git checkout "$dev_branch" || abort "Failed to switch to branch '$dev_branch'."

  # Merge the feature branch into the development branch
  log "Merging feature branch '$current_branch' into '$dev_branch'."
  git merge "$current_branch" --no-edit || abort "Merge failed. Please resolve conflicts manually."

  git push origin "$dev_branch" || abort "Failed to push changes to remote."

  # Handle branch deletion based on configuration
  if [[ "$delete_feature_branch_after_merge" == "true" || "$ask_before_deleting_feature_branch" == "true" ]]; then
    if [[ "$ask_before_deleting_feature_branch" == "true" ]]; then
      read -p "Do you want to delete the feature branch '$current_branch'? (y/n): " delete_response
      if [[ "$delete_response" =~ ^(y|Y|yes|Yes)$ ]]; then
        if [[ -n $(git log "$current_branch" --not "$dev_branch") ]]; then
          abort "Feature branch '$current_branch' contains commits not merged into '$dev_branch'."
        fi
        log "Attempting to delete feature branch '$current_branch'."
        git branch -d "$current_branch" || abort "Failed to delete branch '$current_branch'."
        git push origin --delete "$current_branch" || log "Failed to delete remote branch '$current_branch'."
        log "Feature branch '$current_branch' deleted."
      else
        log "Feature branch '$current_branch' retained."
      fi
    else
      if [[ -n $(git log "$current_branch" --not "$dev_branch") ]]; then
        abort "Feature branch '$current_branch' contains commits not merged into '$dev_branch'."
      fi
      log "Attempting to delete feature branch '$current_branch'."
      git branch -d "$current_branch" || abort "Failed to delete branch '$current_branch'."
      git push origin --delete "$current_branch" || log "Failed to delete remote branch '$current_branch'."
      log "Feature branch '$current_branch' deleted."
    fi
  else
    log "Feature branch '$current_branch' retained."
  fi

  # Apply stashed changes back if needed
  if [[ -n $(git stash list | grep "Auto-stash before closing feature branch") ]]; then
    log "Checking for stashed changes to apply..."
    if [[ -z $(git diff HEAD stash@{0}) ]]; then
      log "No changes from stash need to be applied."
      git stash drop stash@{0} || log "Failed to drop stash. You can manually clean it up."
    else
      log "Applying stashed changes back."
      git stash apply || log "Failed to apply stashed changes. You can manually recover them with 'git stash list'."
      log "Stashed changes successfully applied back to the working directory."
    fi
  else
    log "No stashed changes to apply."
  fi

  # Reminder about uncommitted changes
  if [[ -n $(git status --porcelain) ]]; then
    log "Reminder: You have uncommitted changes in your working directory. Please commit or stash them as needed."
  fi
}
