#!/bin/bash

# This library is sourced only after config.sh and also exposes state to its caller.
# shellcheck disable=SC2034,SC2154

# Function to log actions with simple severity levels
log() {
  local message="$1"
  local level="${2:-INFO}"
  local formatted="[$level] $message"

  if [[ "$level" == "ERROR" ]]; then
    >&2 echo "$formatted"
  else
    echo "$formatted"
  fi

  if [[ "$logging_enabled" == "true" ]]; then
    local timestamped_message
    timestamped_message="$(date '+%Y-%m-%d %H:%M:%S') $formatted"
    echo "$timestamped_message" >> "$log_file"
  fi
}

# Function to run custom hooks (project-level takes priority over global)
run_hook() {
  local hook_name="$1"
  local project_hook_path
  project_hook_path="$(pwd)/.bumpster/hooks/$hook_name"
  local global_hook_path="$BUMPSTER_HOME/hooks/$hook_name"
  local hook_to_run=""

  if [ -x "$project_hook_path" ]; then
    hook_to_run="$project_hook_path"
  elif [ -x "$global_hook_path" ]; then
    hook_to_run="$global_hook_path"
  fi

  if [ -z "$hook_to_run" ]; then
    return 0
  fi

  log "Running hook '$hook_name' from '$hook_to_run'."
  if ! "$hook_to_run"; then
    abort "Hook '$hook_name' failed."
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
  log "$*" "ERROR"
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
  local sync_with_package="${8:-false}"
  local after_bump_branch="${9:-$develop_branch}"
  local before_bump_branch="${10:-$develop_branch}"

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

# Synchronize VERSION file with package.json
SYNC_WITH_PACKAGE_JSON="$sync_with_package"

# Branch to switch to after bumping version
AFTER_BUMP_BRANCH="$after_bump_branch"

# Branch that must be checked out before bumping version
BEFORE_BUMP_BRANCH="$before_bump_branch"
EOF
}

# Function to run an interactive session for configuration
interactive_setup() {
  local config_file="${1:-$global_config_file}"
  echo "Welcome to Bumpster setup!"

  read -r -p "Enter the name for the master branch [default: $default_master_branch]: " master_branch_input
  master_branch=${master_branch_input:-$default_master_branch}

  read -r -p "Enter the name for the develop branch [default: $default_develop_branch]: " develop_branch_input
  develop_branch=${develop_branch_input:-$default_develop_branch}

  read -r -p "Enable logging? (y/n) [default: no]: " logging_input
  logging_enabled="false"
  if [[ "$logging_input" =~ ^(y|Y|yes|Yes)$ ]]; then
    logging_enabled="true"
  fi

  read -r -p "Enter the log file path [default: $default_log_file]: " log_file_input
  log_file=${log_file_input:-$default_log_file}

  read -r -p "Automatically delete feature branches after merge? (y/n) [default: no]: " delete_feature_input
  delete_feature="false"
  if [[ "$delete_feature_input" =~ ^(y|Y|yes|Yes)$ ]]; then
    delete_feature="true"
  fi

  read -r -p "Ask before deleting feature branches? (y/n) [default: yes]: " ask_before_deleting_input
  ask_before_deleting="true"
  if [[ "$ask_before_deleting_input" =~ ^(n|N|no|No)$ ]]; then
    ask_before_deleting="false"
  fi

  read -r -p "Synchronize VERSION file with package.json? (y/n) [default: no]: " sync_with_package_input
  sync_with_package="false"
  if [[ "$sync_with_package_input" =~ ^(y|Y|yes|Yes)$ ]]; then
    sync_with_package="true"
  fi

  read -r -p "Enter the branch to switch to after version bump [default: $default_develop_branch]: " after_bump_branch_input
  after_bump_branch=${after_bump_branch_input:-$default_develop_branch}

  read -r -p "Enter the branch that must be active before bumping [default: $default_develop_branch]: " before_bump_branch_input
  before_bump_branch=${before_bump_branch_input:-$default_develop_branch}

  # Create the config file based on user input
  create_config "$config_file" "$master_branch" "$develop_branch" "$logging_enabled" "$log_file" "$delete_feature" "$ask_before_deleting" "$sync_with_package" "$after_bump_branch" "$before_bump_branch"
}

# Function to create a local config file in the current directory
create_local_config_file() {
  local current_dir
  current_dir=$(pwd)
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
    # The configuration path is selected at runtime by design.
    # shellcheck disable=SC1090
    source "$1"
    master_branch="${GIT_MASTER_BRANCH:-$default_master_branch}"
    develop_branch="${GIT_DEVELOP_BRANCH:-$default_develop_branch}"
    logging_enabled="${ENABLE_LOGGING:-$default_logging}"
    log_file="${LOG_FILE:-$default_log_file}"
    delete_feature_branch_after_merge="${DELETE_FEATURE_BRANCH_AFTER_MERGE:-false}"
    ask_before_deleting_feature_branch="${ASK_BEFORE_DELETING_FEATURE_BRANCH:-true}"
    sync_with_package_json="${SYNC_WITH_PACKAGE_JSON:-false}"
    after_bump_branch="${AFTER_BUMP_BRANCH:-$default_develop_branch}"
    before_bump_branch="${BEFORE_BUMP_BRANCH:-$default_before_bump_branch}"
  fi
}

# Function to perform post-installation steps
post_install() {

  # Log the post-installation process
  log "Performing post-installation steps"

  # Make the main script executable
  log "Setting executable permissions for bumpster.sh"
  # Check if chmod was successful
  if ! chmod +x "$BUMPSTER_HOME/bumpster.sh"; then
    log "Failed to set executable permissions for bumpster.sh" "WARN"
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

  # Optionally create the 'bump' wrapper
  if [[ "$create_bump_wrapper" == "true" ]]; then
    log "Creating 'bump' wrapper for 'bumpster'."
    bump_wrapper="$bin_dir/bump"
    cat > "$bump_wrapper" <<EOF
#!/bin/bash
"\$HOME/.bumpster/bumpster.sh" "\$@"
EOF
    chmod +x "$bump_wrapper"
    log "'bump' wrapper created at $bump_wrapper."
  else
    log "'bump' command is already in use. Wrapper not created."
  fi

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
  if ! remote_version=$(curl -s "$remote_version_file"); then
    log "Failed to fetch remote version information from $remote_version_file." "WARN"
    return 1
  fi
  if [[ -z "$remote_version" ]]; then
    log "Remote version information is empty. Skipping update." "WARN"
    return 1
  fi

  # Compare versions
  if [ "$local_version" != "$remote_version" ]; then
    log "Updating Bumpster from version $local_version to $remote_version..."

    # Create a backup
    local backup_dir="$BUMPSTER_HOME.backup.$local_version"
    if ! cp -r "$BUMPSTER_HOME" "$backup_dir"; then
      abort "Failed to create backup in $backup_dir."
    fi
    log "Backup created at $backup_dir."

    # Download and extract the latest version to a temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    if ! curl -L -# "$version_url" | tar -zxf - --strip-components 1 -C "$temp_dir"; then
      abort "Failed to download and extract the latest Bumpster archive."
    fi

    # Replace the old files with the new ones
    rm -rf "$BUMPSTER_HOME"
    mv "$temp_dir" "$BUMPSTER_HOME"

    # Check if 'bump' command is already in use
    if command -v bump &>/dev/null; then
      log "The command 'bump' is already in use. Wrapper for 'bumpster' will not be created during update."
      create_bump_wrapper="false"
    else
      create_bump_wrapper="true"
    fi

    # Pass the variable to post_install
    export create_bump_wrapper

    # Perform post-installation steps
    post_install

    log "Bumpster updated to version $remote_version."
  else
    log "You are already using the latest version ($local_version)."
  fi
}

# Function to check repository status
check_status() {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  log "Current branch: $current_branch"

  local effective_develop_branch="${develop_branch:-$default_develop_branch}"
  local effective_master_branch="${master_branch:-$default_master_branch}"

  if [[ "$current_branch" == "$effective_develop_branch" ]]; then
    log "You are on the development branch. Ready for new features."
  elif [[ "$current_branch" == "$effective_master_branch" ]]; then
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
  SYNC_WITH_PACKAGE_JSON              Synchronize VERSION file with package.json (default: false)
  AFTER_BUMP_BRANCH                   Branch to switch to after bumping version (default: dev)
  BEFORE_BUMP_BRANCH                  Branch that must be checked out before bumping version (default: dev)
EOS
  exit "${1:-0}"
}

# Function to validate a local branch's configured upstream
validate_release_upstream() {
  local branch_name="$1"
  local configured_remote=""
  local configured_merge=""
  local expected_merge="refs/heads/$branch_name"
  local actual_upstream=""

  configured_remote="$(git config --get "branch.$branch_name.remote" 2>/dev/null || true)"
  configured_merge="$(git config --get "branch.$branch_name.merge" 2>/dev/null || true)"

  if [[ -z "$configured_remote" || -z "$configured_merge" ]]; then
    abort "Branch '$branch_name' must track 'origin/$branch_name' before release."
  fi

  if [[ "$configured_remote" != "origin" || "$configured_merge" != "$expected_merge" ]]; then
    if [[ "$configured_merge" == refs/heads/* ]]; then
      actual_upstream="$configured_remote/${configured_merge#refs/heads/}"
    else
      actual_upstream="$configured_remote:$configured_merge"
    fi
    abort "Branch '$branch_name' tracks '$actual_upstream'; expected 'origin/$branch_name'."
  fi
}

# Function to find one exact ref in git ls-remote output
remote_ref_sha() {
  local remote_refs="$1"
  local ref_name="$2"

  printf '%s\n' "$remote_refs" |
    awk -v expected_ref="$ref_name" '$2 == expected_ref { print $1; exit }'
}

# Function to report preserved local and remote state after a release failure
report_release_failure() {
  local exit_status="$1"
  local current_branch=""
  local current_head=""
  local worktree_state=""
  local tag_state="absent"
  local remote_refs=""
  local remote_develop_sha="absent"
  local remote_master_sha="absent"
  local remote_tag_sha="absent"
  local remote_state="unavailable"
  local remote_check_command=""
  local retry_command=""
  local merge_head_path=""

  if [[ "$exit_status" -eq 0 || "${release_diagnostics_active:-false}" != "true" ]]; then
    return
  fi

  current_branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ -z "$current_branch" ]]; then
    current_branch="detached or unavailable"
  fi
  current_head="$(git rev-parse --short HEAD 2>/dev/null || true)"
  if [[ -z "$current_head" ]]; then
    current_head="unavailable"
  fi
  if worktree_state="$(git status --porcelain 2>/dev/null)"; then
    if [[ -n "$worktree_state" ]]; then
      worktree_state="has local changes"
    else
      worktree_state="clean"
    fi
  else
    worktree_state="unavailable"
  fi
  if git show-ref --verify --quiet "refs/tags/$release_tag_name"; then
    tag_state="present"
  fi

  if remote_refs="$(
    git ls-remote origin \
      "refs/heads/$release_develop_branch" \
      "refs/heads/$release_master_branch" \
      "refs/tags/$release_tag_name" \
      "refs/tags/$release_tag_name^{}" 2>/dev/null
  )"; then
    remote_develop_sha="$(
      remote_ref_sha "$remote_refs" "refs/heads/$release_develop_branch"
    )"
    remote_master_sha="$(
      remote_ref_sha "$remote_refs" "refs/heads/$release_master_branch"
    )"
    remote_tag_sha="$(
      remote_ref_sha "$remote_refs" "refs/tags/$release_tag_name"
    )"
    remote_develop_sha="${remote_develop_sha:-absent}"
    remote_master_sha="${remote_master_sha:-absent}"
    remote_tag_sha="${remote_tag_sha:-absent}"

    if [[ "$remote_develop_sha" == "$release_initial_remote_develop_sha" &&
          "$remote_master_sha" == "$release_initial_remote_master_sha" &&
          "$remote_tag_sha" == "absent" ]]; then
      remote_state="unchanged"
    else
      remote_state="changed"
    fi
  fi

  log "Release '$release_tag_name' stopped during '$release_stage'." "ERROR"
  if [[ "${release_published:-false}" == "true" ]]; then
    log "The release was published before this later step failed. Do not recreate its tag or repeat the publication." "ERROR"
  else
    log "No automatic rollback was attempted; local release state was preserved for inspection." "ERROR"
  fi
  log "Recovery state: branch '$current_branch', HEAD '$current_head', working tree $worktree_state, local tag $tag_state." "ERROR"

  case "$remote_state" in
    unchanged)
      log "Remote release refs are unchanged from preflight." "ERROR"
      ;;
    changed)
      log "Remote release refs differ from preflight; inspect them before taking any recovery action." "ERROR"
      ;;
    *)
      log "Remote release refs could not be verified; do not assume publication failed or succeeded." "ERROR"
      ;;
  esac

  printf -v remote_check_command \
    'git ls-remote origin %q %q %q %q' \
    "refs/heads/$release_develop_branch" \
    "refs/heads/$release_master_branch" \
    "refs/tags/$release_tag_name" \
    "refs/tags/$release_tag_name^{}"
  log "Inspect the preserved state with:" "ERROR"
  log "  git status" "ERROR"
  log "  git log --oneline --decorate --graph --all" "ERROR"
  log "  $remote_check_command" "ERROR"

  merge_head_path="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null || true)"
  if [[ -n "$merge_head_path" && -f "$merge_head_path" ]]; then
    log "An unfinished merge is present. To abandon only that merge, run:" "ERROR"
    log "  git merge --abort" "ERROR"
  fi

  if [[ "$remote_state" == "unchanged" &&
        "$release_stage" == "atomic publication" &&
        "$tag_state" == "present" ]]; then
    printf -v retry_command \
      'git push --atomic origin %q %q %q' \
      "refs/heads/$release_develop_branch" \
      "refs/heads/$release_master_branch" \
      "refs/tags/$release_tag_name"
    log "After fixing the rejection, the preserved release can be retried with:" "ERROR"
    log "  $retry_command" "ERROR"
  fi
}

# EXIT trap entry point that preserves the original failure status
release_exit_handler() {
  local exit_status="$1"

  trap - EXIT
  report_release_failure "$exit_status"
  exit "$exit_status"
}

# Function to validate release refs before the first local mutation
preflight_release() {
  local new_version="$1"
  local develop_branch_name="$2"
  local master_branch_name="$3"
  local release_tag="v$new_version"
  local remote_develop_ref="refs/remotes/origin/$develop_branch_name"
  local remote_master_ref="refs/remotes/origin/$master_branch_name"
  local local_master_ref="refs/heads/$master_branch_name"
  local master_base_ref=""
  local remote_refs=""
  local remote_develop_sha=""
  local remote_master_sha=""
  local remote_tag_sha=""

  log "Running release preflight checks."

  if ! git check-ref-format --branch "$develop_branch_name" >/dev/null 2>&1; then
    abort "Configured development branch name '$develop_branch_name' is invalid."
  fi
  if ! git check-ref-format --branch "$master_branch_name" >/dev/null 2>&1; then
    abort "Configured main branch name '$master_branch_name' is invalid."
  fi
  if [[ "$develop_branch_name" == "$master_branch_name" ]]; then
    abort "Development and main branch names must be different."
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    abort "Remote 'origin' is not configured."
  fi
  if ! git remote get-url --push origin >/dev/null 2>&1; then
    abort "Remote 'origin' has no push URL configured."
  fi

  validate_release_upstream "$develop_branch_name"
  if git show-ref --verify --quiet "$local_master_ref"; then
    validate_release_upstream "$master_branch_name"
  fi

  if ! remote_refs="$(
    git ls-remote origin \
      "refs/heads/$develop_branch_name" \
      "refs/heads/$master_branch_name" \
      "refs/tags/$release_tag" \
      "refs/tags/$release_tag^{}"
  )"; then
    abort "Failed to query release refs from origin. Check its URL and access."
  fi

  remote_develop_sha="$(
    remote_ref_sha "$remote_refs" "refs/heads/$develop_branch_name"
  )"
  remote_master_sha="$(
    remote_ref_sha "$remote_refs" "refs/heads/$master_branch_name"
  )"
  remote_tag_sha="$(remote_ref_sha "$remote_refs" "refs/tags/$release_tag")"

  if [[ -n "$remote_tag_sha" ]]; then
    abort "Release tag '$release_tag' already exists on origin."
  fi
  if git show-ref --verify --quiet "refs/tags/$release_tag"; then
    abort "Release tag '$release_tag' already exists locally."
  fi

  git fetch --prune origin ||
    abort "Failed to fetch current state from origin. Check its URL, access, and fetch configuration."

  if [[ -n "$remote_develop_sha" ]] &&
     ! git show-ref --verify --quiet "$remote_develop_ref"; then
    abort "Remote branch 'origin/$develop_branch_name' exists but was not fetched. Check remote.origin.fetch."
  fi
  if [[ -n "$remote_master_sha" ]] &&
     ! git show-ref --verify --quiet "$remote_master_ref"; then
    abort "Remote branch 'origin/$master_branch_name' exists but was not fetched. Check remote.origin.fetch."
  fi

  if [[ -n "$remote_develop_sha" ]]; then
    if ! git merge-base --is-ancestor "$remote_develop_ref" "$develop_branch_name"; then
      abort "Local branch '$develop_branch_name' is behind or has diverged from 'origin/$develop_branch_name'."
    fi
  fi

  if git show-ref --verify --quiet "$local_master_ref" &&
     [[ -n "$remote_master_sha" ]]; then
    if [[ "$(git rev-parse "$local_master_ref")" != "$(git rev-parse "$remote_master_ref")" ]]; then
      abort "Local branch '$master_branch_name' does not match 'origin/$master_branch_name'."
    fi
  fi

  if git show-ref --verify --quiet "$local_master_ref"; then
    master_base_ref="$local_master_ref"
  elif [[ -n "$remote_master_sha" ]]; then
    master_base_ref="$remote_master_ref"
  fi

  if [[ -n "$master_base_ref" ]] &&
     ! git merge-base --is-ancestor "$master_base_ref" "$develop_branch_name"; then
    abort "Development branch '$develop_branch_name' does not contain the current '$master_branch_name' history."
  fi

  release_initial_remote_develop_sha="${remote_develop_sha:-absent}"
  release_initial_remote_master_sha="${remote_master_sha:-absent}"

  log "Release preflight checks passed."
}

# Function to check if a branch exists locally or remotely, and create it if necessary
check_or_create_branch() {
  local branch_name="$1"
  local remote_ref="refs/remotes/origin/$branch_name"

  # Check if the branch exists locally
  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    if git show-ref --verify --quiet "$remote_ref"; then
      log "Branch '$branch_name' exists only on origin. Creating a local tracking branch."
      git checkout -b "$branch_name" --track "origin/$branch_name" ||
        abort "Failed to create tracking branch '$branch_name' from 'origin/$branch_name'."
    else
      log "Branch '$branch_name' does not exist. Creating it from the current HEAD."
      git checkout -b "$branch_name" || abort "Failed to create branch '$branch_name'."
    fi
    log "Branch '$branch_name' successfully created locally."
  else
    log "Branch '$branch_name' already exists locally."
    git checkout "$branch_name" || abort "Failed to switch to branch '$branch_name'."
  fi
}

# Function to create a feature branch from the current dev branch
create_feature() {
  # Use the configured develop branch or fall back to default_develop_branch
  local dev_branch="${develop_branch:-$default_develop_branch}"

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
    read -r -p "Enter the name for the new feature branch: " feature_branch_name
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
    abort "Branch '$feature_branch_name' already exists. Please choose a different name."
  fi

  # Create and switch to the feature branch
  log "Creating feature branch '$feature_branch_name' from '$current_branch'."
  git checkout -b "$feature_branch_name" || abort "Failed to create branch '$feature_branch_name'."
  log "Feature branch '$feature_branch_name' created and checked out."
}

# Function to abort feature closing while preserving an exact operation-owned stash
abort_close_feature() {
  local message="$1"
  local stash_oid="${2:-}"
  local feature_branch_name="${3:-}"

  if [[ -n "$stash_oid" ]]; then
    log "Uncommitted changes from '$feature_branch_name' remain preserved in stash commit '$stash_oid'." "ERROR"
    log "Inspect 'git stash list' and the current branch state before restoring them manually." "ERROR"
  fi
  abort "$message"
}

# Function to find the reflog selector for one exact stash commit
find_stash_ref_by_oid() {
  local stash_oid="$1"

  git stash list --format='%H %gd' |
    awk -v expected_oid="$stash_oid" '$1 == expected_oid { print $2; exit }'
}

# Function to restore and remove only the stash created by close_feature
restore_close_feature_stash() {
  local stash_oid="$1"
  local target_branch="$2"
  local feature_branch_name="$3"
  local current_branch=""
  local stash_ref=""

  current_branch="$(git rev-parse --abbrev-ref HEAD)" ||
    abort_close_feature "Could not determine the branch used for stash restoration." \
      "$stash_oid" "$feature_branch_name"
  if [[ "$current_branch" != "$target_branch" ]]; then
    abort_close_feature \
      "Refusing to restore feature changes on '$current_branch'; expected '$target_branch'." \
      "$stash_oid" "$feature_branch_name"
  fi

  log "Restoring stashed feature changes on '$target_branch'."
  git stash apply --index "$stash_oid" ||
    abort_close_feature \
      "Failed to restore stashed changes on '$target_branch'. Resolve the working tree before retrying." \
      "$stash_oid" "$feature_branch_name"

  stash_ref="$(find_stash_ref_by_oid "$stash_oid")"
  if [[ -z "$stash_ref" ]]; then
    log "Restored changes, but the operation-owned stash entry could not be found for cleanup." "WARN"
    return
  fi
  git stash drop "$stash_ref" >/dev/null ||
    log "Restored changes, but failed to drop operation-owned stash '$stash_ref'." "WARN"
}

# Function to close the current feature branch
close_feature() {
  # Use the configured develop and master branches, falling back to defaults
  local dev_branch="${develop_branch:-$default_develop_branch}"
  local master_branch_name="${master_branch:-$default_master_branch}"
  local current_branch=""
  local stash_response=""
  local delete_response=""
  local stash_before=""
  local created_stash_oid=""

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    abort "Git repository not found. Please initialize git first."
  fi
  current_branch="$(git rev-parse --abbrev-ref HEAD)" ||
    abort "Could not determine the current branch."

  # Ensure the current branch is a feature branch before changing stash state
  if [[ "$current_branch" == "$dev_branch" || "$current_branch" == "$master_branch_name" ]]; then
    abort "Cannot close a feature branch from '$current_branch'. Please switch to a feature branch."
  fi
  if [[ "$current_branch" == "HEAD" ]]; then
    abort "Cannot close a feature branch from detached HEAD."
  fi
  if ! git show-ref --verify --quiet "refs/heads/$dev_branch"; then
    abort "Development branch '$dev_branch' does not exist locally."
  fi

  # Require an operation-owned stash before checkout or merge
  if [[ -n $(git status --porcelain) ]]; then
    log "You have uncommitted changes in your working directory."
    read -r -p \
      "Stash them and restore them on '$dev_branch' after the merge? (y/n): " \
      stash_response
    if [[ "$stash_response" =~ ^(y|Y|yes|Yes)$ ]]; then
      stash_before="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
      git stash push --include-untracked -m "Bumpster close-feature: $current_branch" ||
        abort "Failed to stash feature changes."
      created_stash_oid="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
      if [[ -z "$created_stash_oid" || "$created_stash_oid" == "$stash_before" ]]; then
        abort "Git did not create a new stash for the feature changes."
      fi
      if [[ -n $(git status --porcelain) ]]; then
        abort_close_feature \
          "Some working tree changes could not be stashed. Feature closing was not started." \
          "$created_stash_oid" "$current_branch"
      fi
      log "Feature changes stashed as '$created_stash_oid'."
    else
      abort "Feature closing requires a clean working tree. Commit or stash the changes and retry."
    fi
  fi

  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$current_branch" ]]; then
    abort_close_feature "Current branch mismatch. Expected '$current_branch'." \
      "$created_stash_oid" "$current_branch"
  fi

  # Switch to the development branch
  log "Switching to development branch '$dev_branch'."
  git checkout "$dev_branch" ||
    abort_close_feature "Failed to switch to branch '$dev_branch'." \
      "$created_stash_oid" "$current_branch"

  # Merge the feature branch into the development branch
  log "Merging feature branch '$current_branch' into '$dev_branch'."
  git merge "$current_branch" --no-edit ||
    abort_close_feature "Merge failed. Please resolve conflicts manually." \
      "$created_stash_oid" "$current_branch"

  git push origin "$dev_branch" ||
    abort_close_feature "Failed to push changes to remote." \
      "$created_stash_oid" "$current_branch"

  # Restore only the stash created by this invocation, always on the development branch
  if [[ -n "$created_stash_oid" ]]; then
    restore_close_feature_stash "$created_stash_oid" "$dev_branch" "$current_branch"
    created_stash_oid=""
  fi

  # Handle branch deletion based on configuration
  if [[ "$delete_feature_branch_after_merge" == "true" || "$ask_before_deleting_feature_branch" == "true" ]]; then
    if [[ "$ask_before_deleting_feature_branch" == "true" ]]; then
      read -r -p "Do you want to delete the feature branch '$current_branch'? (y/n): " delete_response
      if [[ "$delete_response" =~ ^(y|Y|yes|Yes)$ ]]; then
        if [[ -n $(git log "$current_branch" --not "$dev_branch") ]]; then
          abort "Feature branch '$current_branch' contains commits not merged into '$dev_branch'."
        fi
        log "Attempting to delete feature branch '$current_branch'."
        git branch -d "$current_branch" || abort "Failed to delete branch '$current_branch'."
        if git ls-remote --exit-code origin "$current_branch" &>/dev/null; then
          git push origin --delete "$current_branch" || log "Failed to delete remote branch '$current_branch'." "WARN"
          log "Remote branch '$current_branch' deleted."
        else
          log "Remote branch '$current_branch' does not exist. Skipping remote deletion."
        fi
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
      if git ls-remote --exit-code origin "$current_branch" &>/dev/null; then
        git push origin --delete "$current_branch" || log "Failed to delete remote branch '$current_branch'." "WARN"
        log "Remote branch '$current_branch' deleted."
      else
        log "Remote branch '$current_branch' does not exist. Skipping remote deletion."
      fi
      log "Feature branch '$current_branch' deleted."
    fi
  else
    log "Feature branch '$current_branch' retained."
  fi

  # Reminder about uncommitted changes
  if [[ -n $(git status --porcelain) ]]; then
    log "Reminder: You have uncommitted changes in your working directory. Please commit or stash them as needed."
  fi
}
