#!/bin/bash

# This library is sourced only after config.sh and also exposes state to its caller.
# shellcheck disable=SC2034,SC2154

# Function to log actions with simple severity levels
log() {
  local message="$1"
  local level="${2:-INFO}"
  local formatted="[$level] $message"
  local terminal_message="${3:-$message}"
  local terminal_formatted="[$level] $terminal_message"

  if [[ "$level" == "ERROR" ]]; then
    printf '%s\n' "$terminal_formatted" >&2
  else
    printf '%s\n' "$terminal_formatted"
  fi

  if [[ "$logging_enabled" == "true" ]]; then
    local timestamped_message
    timestamped_message="$(date '+%Y-%m-%d %H:%M:%S') $formatted"
    if ! { printf '%s\n' "$timestamped_message" >> "$log_file"; } 2>/dev/null; then
      if [[ "${logging_failure_reported:-false}" != "true" ]]; then
        printf '[WARN] Could not write log file %q. Continuing without file logging.\n' \
          "$log_file" >&2
        logging_failure_reported="true"
      fi
    fi
  fi

  return 0
}

# Return success when the selected output descriptor is an interactive terminal.
log_output_is_terminal() {
  local descriptor="$1"

  [[ -t "$descriptor" ]]
}

# Highlight values only in interactive terminal output. The plain message is
# still used for redirected output and optional file logging.
log_highlighted() {
  local message="$1"
  shift
  local terminal_message="$message"
  local value
  local colored_value

  if [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]] &&
    log_output_is_terminal 1; then
    for value in "$@"; do
      [[ -n "$value" ]] || continue
      [[ "$value" =~ ^[[:alnum:]._-]+$ ]] || continue
      printf -v colored_value '\033[1;33m%s\033[0m' "$value"
      # Values are restricted above so they cannot act as glob patterns here.
      # shellcheck disable=SC2295
      terminal_message="${terminal_message//$value/$colored_value}"
    done
  fi

  log "$message" "INFO" "$terminal_message"
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

# Function to validate package.json before any release mutation
validate_package_json_for_sync() {
  local package_file="$1"

  if ! command -v node >/dev/null 2>&1; then
    log "Node.js is required when SYNC_WITH_PACKAGE_JSON is enabled." "ERROR"
    return 1
  fi
  if ! node --version >/dev/null 2>&1; then
    log "Node.js was found but could not be executed for package.json synchronization." "ERROR"
    return 1
  fi

  node - "$package_file" <<'NODE'
const fs = require("fs");

const packageFile = process.argv[2];

try {
  const fileStat = fs.lstatSync(packageFile);
  if (fileStat.isSymbolicLink() || !fileStat.isFile()) {
    throw new Error("the path must be a regular file, not a symbolic link");
  }

  const packageData = JSON.parse(fs.readFileSync(packageFile, "utf8"));
  if (packageData === null || Array.isArray(packageData) || typeof packageData !== "object") {
    throw new Error("the root JSON value must be an object");
  }
  if (
    Object.prototype.hasOwnProperty.call(packageData, "version") &&
    typeof packageData.version !== "string"
  ) {
    throw new Error("the root version field must be a string");
  }
} catch (error) {
  console.error(`Invalid ${packageFile}: ${error.message}`);
  process.exit(1);
}
NODE
}

# Function to atomically update only the root package.json version field
update_package_json_version() {
  local package_file="$1"
  local new_version="$2"

  node - "$package_file" "$new_version" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const packageFile = process.argv[2];
const newVersion = process.argv[3];
const directory = path.dirname(packageFile);
const basename = path.basename(packageFile);
const temporaryFile = path.join(
  directory,
  `.${basename}.bumpster-${process.pid}-${Date.now()}-${crypto.randomBytes(6).toString("hex")}.tmp`
);
let temporaryFd = null;

try {
  const fileStat = fs.lstatSync(packageFile);
  if (fileStat.isSymbolicLink() || !fileStat.isFile()) {
    throw new Error("the path must be a regular file, not a symbolic link");
  }

  const source = fs.readFileSync(packageFile, "utf8");
  const packageData = JSON.parse(source);
  if (packageData === null || Array.isArray(packageData) || typeof packageData !== "object") {
    throw new Error("the root JSON value must be an object");
  }
  if (
    Object.prototype.hasOwnProperty.call(packageData, "version") &&
    typeof packageData.version !== "string"
  ) {
    throw new Error("the root version field must be a string");
  }

  packageData.version = newVersion;

  const indentMatch = source.match(/\n([ \t]+)"/);
  const indent = indentMatch ? indentMatch[1] : undefined;
  const usesCrLf = source.includes("\r\n");
  const hasFinalNewline = source.endsWith("\n");
  let output = JSON.stringify(packageData, null, indent);
  if (usesCrLf) {
    output = output.replace(/\n/g, "\r\n");
  }
  if (hasFinalNewline) {
    output += usesCrLf ? "\r\n" : "\n";
  }

  temporaryFd = fs.openSync(temporaryFile, "wx", fileStat.mode & 0o777);
  fs.writeFileSync(temporaryFd, output, "utf8");
  fs.fsyncSync(temporaryFd);
  fs.closeSync(temporaryFd);
  temporaryFd = null;
  fs.renameSync(temporaryFile, packageFile);
} catch (error) {
  console.error(`Could not update ${packageFile}: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (temporaryFd !== null) {
    try {
      fs.closeSync(temporaryFd);
    } catch (_) {
      // Preserve the original error.
    }
  }
  try {
    fs.unlinkSync(temporaryFile);
  } catch (error) {
    if (error.code !== "ENOENT") {
      console.error(`Could not remove temporary file ${temporaryFile}: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
NODE
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

# Function to require Git and an initialized repository for Git commands
require_git_repository() {
  if ! command -v git >/dev/null 2>&1; then
    abort "Git is not installed. Please install it and try again."
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    abort "Git repository not found. Please initialize git first."
  fi
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
  current_dir="$(pwd)" ||
    abort "Could not determine the current directory for local configuration."
  local local_config_file="$current_dir/.bumpsterrc"

  if [ -f "$local_config_file" ]; then
    log "Local configuration file already exists at: $local_config_file"
  else
    interactive_setup "$local_config_file" ||
      abort "Could not create local configuration file at '$local_config_file'."
    log "Local configuration file successfully created at: $local_config_file"
  fi
}

# Function to load configuration from a config file
load_config() {
  local config_file="$1"

  if [ -f "$config_file" ]; then
    # The configuration path is selected at runtime by design.
    # shellcheck disable=SC1090
    source "$config_file" ||
      abort "Failed to load configuration from '$config_file'."
    master_branch="${GIT_MASTER_BRANCH:-$default_master_branch}"
    develop_branch="${GIT_DEVELOP_BRANCH:-$default_develop_branch}"
    logging_enabled="${ENABLE_LOGGING:-$default_logging}"
    log_file="${LOG_FILE:-$default_log_file}"
    delete_feature_branch_after_merge="${DELETE_FEATURE_BRANCH_AFTER_MERGE:-false}"
    ask_before_deleting_feature_branch="${ASK_BEFORE_DELETING_FEATURE_BRANCH:-true}"
    sync_with_package_json="${SYNC_WITH_PACKAGE_JSON:-false}"
    after_bump_branch="${AFTER_BUMP_BRANCH:-$develop_branch}"
    before_bump_branch="${BEFORE_BUMP_BRANCH:-$develop_branch}"
  fi
}

# Write one command wrapper atomically.
write_command_wrapper() {
  local wrapper_path="$1"
  local temporary_wrapper

  temporary_wrapper="$(mktemp "$bin_dir/.wrapper.XXXXXX")" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'BUMPSTER_HOME=%q\n' "$BUMPSTER_HOME"
    printf 'export BUMPSTER_HOME\n'
    # The generated wrapper must contain the literal runtime variable references.
    # shellcheck disable=SC2016
    printf 'exec "$BUMPSTER_HOME/bumpster.sh" "$@"\n'
  } > "$temporary_wrapper" || return 1
  chmod +x "$temporary_wrapper" || return 1
  mv "$temporary_wrapper" "$wrapper_path"
}

# Function to perform post-installation steps
post_install() {
  log "Performing post-installation steps"

  if ! chmod +x "$BUMPSTER_HOME/bumpster.sh"; then
    log "Failed to make bumpster.sh executable." "ERROR"
    return 1
  fi
  if ! mkdir -p "$bin_dir"; then
    log "Failed to create the command directory." "ERROR"
    return 1
  fi
  if ! write_command_wrapper "$bin_dir/bumpster"; then
    log "Failed to create the bumpster wrapper." "ERROR"
    return 1
  fi

  if [[ "${create_bump_wrapper:-false}" == "true" ]]; then
    if ! write_command_wrapper "$bin_dir/bump"; then
      log "Failed to create the bump wrapper." "ERROR"
      return 1
    fi
    log "'bump' wrapper created at $bin_dir/bump."
  else
    log "The command 'bump' is already in use. Wrapper not created."
  fi
}

runtime_version_is_greater() {
  local candidate="$1"
  local reference="$2"
  local candidate_major candidate_minor candidate_patch
  local reference_major reference_minor reference_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
  IFS=. read -r reference_major reference_minor reference_patch <<< "$reference"

  if ((candidate_major != reference_major)); then
    ((candidate_major > reference_major))
    return
  fi
  if ((candidate_minor != reference_minor)); then
    ((candidate_minor > reference_minor))
    return
  fi
  ((candidate_patch > reference_patch))
}

runtime_download_file() {
  local url="$1"
  local output_path="$2"
  local protocol="=https"

  if [[ "$url" == file://* ]]; then
    protocol="=file"
  fi

  curl \
    --disable \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto "$protocol" \
    --output "$output_path" \
    "$url"
}

runtime_calculate_sha256() {
  local file_path="$1"

  case "$runtime_sha256_command" in
    shasum)
      shasum -a 256 "$file_path" | awk '{print $1}'
      ;;
    sha256sum)
      sha256sum "$file_path" | awk '{print $1}'
      ;;
    *)
      return 1
      ;;
  esac
}

runtime_parse_release_checksum() {
  local checksum_path="$1"
  local checksum_line

  checksum_line="$(<"$checksum_path")" || return 1
  if [[ ! "$checksum_line" =~ ^([0-9a-f]{64})[[:space:]][[:space:]](bumpster-((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))\.tar\.gz)$ ]]; then
    log "SHA256SUMS does not contain one valid Bumpster runtime asset." "ERROR"
    return 1
  fi

  runtime_release_checksum="${BASH_REMATCH[1]}"
  runtime_archive_name="${BASH_REMATCH[2]}"
  runtime_release_version="${BASH_REMATCH[3]}"
}

runtime_verify_release_archive() {
  local archive_path="$1"
  local actual_checksum
  local expected_entries
  local actual_entries
  local runtime_file
  local version_output

  actual_checksum="$(runtime_calculate_sha256 "$archive_path")" ||
    return 1
  if [[ "$actual_checksum" != "$runtime_release_checksum" ]]; then
    log "Runtime archive checksum mismatch." "ERROR"
    return 1
  fi

  expected_entries="$(
    printf '%s\n' \
      "bumpster-$runtime_release_version/" \
      "bumpster-$runtime_release_version/LICENSE" \
      "bumpster-$runtime_release_version/VERSION" \
      "bumpster-$runtime_release_version/bumpster.sh" \
      "bumpster-$runtime_release_version/config.sh" \
      "bumpster-$runtime_release_version/lib/" \
      "bumpster-$runtime_release_version/lib/BUMPSTER_LOGO.ASCII" \
      "bumpster-$runtime_release_version/lib/functions.sh"
  )"
  actual_entries="$(tar -tzf "$archive_path")" || {
    log "Could not read the runtime archive." "ERROR"
    return 1
  }
  if [[ "$actual_entries" != "$expected_entries" ]]; then
    log "Runtime archive contents do not match the whitelist." "ERROR"
    return 1
  fi

  if ! tar -xzf "$archive_path" -C "$runtime_temporary_root"; then
    log "Could not extract the runtime archive." "ERROR"
    return 1
  fi
  runtime_staged_home="$runtime_temporary_root/bumpster-$runtime_release_version"

  if [[ ! -d "$runtime_staged_home" || -L "$runtime_staged_home" ||
    ! -d "$runtime_staged_home/lib" || -L "$runtime_staged_home/lib" ]]; then
    log "Runtime archive directory structure is unsafe." "ERROR"
    return 1
  fi
  for runtime_file in \
    LICENSE VERSION bumpster.sh config.sh \
    lib/BUMPSTER_LOGO.ASCII lib/functions.sh; do
    if [[ ! -f "$runtime_staged_home/$runtime_file" ||
      -L "$runtime_staged_home/$runtime_file" ]]; then
      log "Runtime archive contains an unsafe file: $runtime_file" "ERROR"
      return 1
    fi
  done
  if [[ "$(<"$runtime_staged_home/VERSION")" != "$runtime_release_version" ]]; then
    log "Runtime VERSION does not match the Release asset." "ERROR"
    return 1
  fi

  version_output="$(
    HOME="$HOME" \
      BUMPSTER_HOME="$runtime_staged_home" \
      bash "$runtime_staged_home/bumpster.sh" --version
  )" || {
    log "Packaged Bumpster failed its version smoke test." "ERROR"
    return 1
  }
  if [[ "$version_output" != "Bumpster version: $runtime_release_version" ]]; then
    log "Packaged Bumpster reported an unexpected version." "ERROR"
    return 1
  fi
}

runtime_remove_temporary_root() {
  local temporary_name

  if [[ -z "$runtime_temporary_root" || ! -e "$runtime_temporary_root" ]]; then
    return
  fi
  if [[ "$(dirname "$runtime_temporary_root")" != "$runtime_target_parent" ]]; then
    log "Refusing to remove unexpected temporary path: $runtime_temporary_root" "ERROR"
    return
  fi

  temporary_name="$(basename "$runtime_temporary_root")"
  case "$temporary_name" in
    ".$runtime_target_name.update."*)
      rm -rf -- "$runtime_temporary_root"
      ;;
    *)
      log "Refusing to remove unexpected temporary path: $runtime_temporary_root" "ERROR"
      ;;
  esac
}

runtime_rollback_update() {
  local failed_runtime=""

  if [[ "$runtime_update_complete" == "true" ]]; then
    return
  fi

  if [[ "$runtime_new_moved" == "true" && -e "$runtime_target_home" ]]; then
    failed_runtime="$runtime_temporary_root/failed-runtime"
    if ! mv "$runtime_target_home" "$failed_runtime"; then
      log "Could not move the failed runtime away from $runtime_target_home." "ERROR"
      return
    fi
    runtime_new_moved=false
  fi

  if [[ "$runtime_previous_moved" == "true" &&
    -d "$runtime_previous_home" ]]; then
    if mv "$runtime_previous_home" "$runtime_target_home"; then
      runtime_previous_moved=false
      rmdir "$runtime_backup_dir" 2>/dev/null || true
      runtime_backup_dir=""
      log "Previous Bumpster installation restored." "WARN"
    else
      log "Automatic rollback failed. Previous installation remains at $runtime_previous_home." "ERROR"
    fi
  fi
}

runtime_update_cleanup() {
  runtime_rollback_update
  if [[ "$runtime_update_complete" != "true" &&
    -n "$runtime_backup_dir" && -d "$runtime_backup_dir" ]]; then
    rmdir "$runtime_backup_dir" 2>/dev/null || true
  fi
  runtime_remove_temporary_root
}

runtime_resolve_update_home() {
  local requested_parent
  local physical_home

  if [[ -z "$BUMPSTER_HOME" || "$BUMPSTER_HOME" != /* ]]; then
    log "BUMPSTER_HOME must be an absolute path." "ERROR"
    return 1
  fi
  runtime_target_name="$(basename "$BUMPSTER_HOME")"
  if [[ -z "$runtime_target_name" || "$runtime_target_name" == "." ||
    "$runtime_target_name" == ".." ]]; then
    log "BUMPSTER_HOME has an unsafe final path component." "ERROR"
    return 1
  fi

  requested_parent="$(dirname "$BUMPSTER_HOME")"
  if ! runtime_target_parent="$(cd "$requested_parent" && pwd -P)"; then
    log "Could not resolve the parent directory for BUMPSTER_HOME." "ERROR"
    return 1
  fi
  runtime_target_home="$runtime_target_parent/$runtime_target_name"
  physical_home="$(cd "$HOME" && pwd -P)" || return 1

  if [[ "$runtime_target_home" == "/" ||
    "$runtime_target_home" == "$physical_home" ]]; then
    log "Refusing to use a broad directory as BUMPSTER_HOME." "ERROR"
    return 1
  fi
  if [[ -L "$runtime_target_home" || ! -d "$runtime_target_home" ]]; then
    log "BUMPSTER_HOME must be an existing directory, not a symbolic link." "ERROR"
    return 1
  fi

  BUMPSTER_HOME="$runtime_target_home"
  bin_dir="$BUMPSTER_HOME/bin"
  local_version_file="$BUMPSTER_HOME/VERSION"
}

# Function to update Bumpster to the latest stable GitHub Release.
update_bumpster() (
  local checksum_path
  local archive_path
  local local_version
  local existing_bump=""
  local existing_bump_parent=""
  local physical_existing_bump=""
  local runtime_sha256_command=""

  runtime_target_parent=""
  runtime_target_name=""
  runtime_target_home=""
  runtime_temporary_root=""
  runtime_staged_home=""
  runtime_backup_dir=""
  runtime_previous_home=""
  runtime_previous_moved=false
  runtime_new_moved=false
  runtime_update_complete=false
  runtime_release_checksum=""
  runtime_archive_name=""
  runtime_release_version=""

  if [[ "${BUMPSTER_INSTALL_METHOD:-standalone}" == "homebrew" ]]; then
    log "Bumpster is managed by Homebrew. Use 'brew upgrade bumpster' to update." "ERROR"
    return 1
  fi

  trap runtime_update_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  for required_command in \
    awk basename chmod cp curl dirname mktemp mkdir mv rm rmdir tar; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
      log "$required_command is required for updates." "ERROR"
      return 1
    fi
  done
  if command -v shasum >/dev/null 2>&1; then
    runtime_sha256_command="shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    runtime_sha256_command="sha256sum"
  else
    log "shasum or sha256sum is required for updates." "ERROR"
    return 1
  fi

  runtime_resolve_update_home || return 1
  case "$release_download_url" in
    https://*)
      ;;
    file://*)
      if [[ "${BUMPSTER_TEST_ALLOW_FILE_RELEASES:-false}" != "true" ]]; then
        log "Release downloads must use HTTPS." "ERROR"
        return 1
      fi
      ;;
    *)
      log "Release downloads must use HTTPS." "ERROR"
      return 1
      ;;
  esac

  if [[ ! -f "$local_version_file" ]]; then
    log "Local VERSION is missing; use the versioned installer to recover." "ERROR"
    return 1
  fi
  local_version="$(<"$local_version_file")"
  if [[ ! "$local_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    log "Local VERSION is invalid; use the versioned installer to recover." "ERROR"
    return 1
  fi

  runtime_temporary_root="$(
    mktemp -d "$runtime_target_parent/.$runtime_target_name.update.XXXXXX"
  )" || {
    log "Could not create a temporary update directory." "ERROR"
    return 1
  }
  checksum_path="$runtime_temporary_root/SHA256SUMS"

  if ! runtime_download_file \
    "${release_download_url%/}/SHA256SUMS" \
    "$checksum_path"; then
    log "Could not download SHA256SUMS." "ERROR"
    return 1
  fi
  runtime_parse_release_checksum "$checksum_path" || return 1

  if [[ "$local_version" == "$runtime_release_version" ]]; then
    log "You are already using the latest version ($local_version)."
    runtime_update_complete=true
    return 0
  fi
  if ! runtime_version_is_greater "$runtime_release_version" "$local_version"; then
    log "Refusing to downgrade from $local_version to $runtime_release_version." "ERROR"
    return 1
  fi

  archive_path="$runtime_temporary_root/$runtime_archive_name"
  log "Updating Bumpster from $local_version to $runtime_release_version..."
  if ! runtime_download_file \
    "${release_download_url%/}/$runtime_archive_name" \
    "$archive_path"; then
    log "Could not download $runtime_archive_name." "ERROR"
    return 1
  fi
  runtime_verify_release_archive "$archive_path" || return 1

  if [[ -e "$runtime_target_home/hooks" ]]; then
    if [[ ! -d "$runtime_target_home/hooks" ]] ||
      ! cp -R "$runtime_target_home/hooks" "$runtime_staged_home/hooks"; then
      log "Could not preserve user hooks." "ERROR"
      return 1
    fi
  fi

  existing_bump="$(command -v bump 2>/dev/null || true)"
  if [[ "$existing_bump" == /* ]]; then
    existing_bump_parent="$(dirname "$existing_bump")"
    if physical_existing_bump="$(
      cd "$existing_bump_parent" 2>/dev/null &&
        printf '%s/%s' "$(pwd -P)" "$(basename "$existing_bump")"
    )"; then
      existing_bump="$physical_existing_bump"
    fi
  fi
  if [[ -z "$existing_bump" ||
    "$existing_bump" == "$runtime_target_home/bin/bump" ]]; then
    create_bump_wrapper=true
  else
    create_bump_wrapper=false
  fi

  runtime_backup_dir="$(
    mktemp -d \
      "$runtime_target_parent/$runtime_target_name.backup.$local_version.XXXXXX"
  )" || {
    log "Could not create a backup directory." "ERROR"
    return 1
  }
  runtime_previous_home="$runtime_backup_dir/runtime"
  runtime_previous_moved=true
  if ! mv "$runtime_target_home" "$runtime_previous_home"; then
    runtime_previous_moved=false
    log "Could not move the existing installation to $runtime_previous_home." "ERROR"
    return 1
  fi

  runtime_new_moved=true
  if ! mv "$runtime_staged_home" "$runtime_target_home"; then
    runtime_new_moved=false
    log "Could not activate the verified runtime." "ERROR"
    return 1
  fi

  BUMPSTER_HOME="$runtime_target_home"
  bin_dir="$BUMPSTER_HOME/bin"
  if ! post_install; then
    log "Could not finish the updated installation." "ERROR"
    return 1
  fi

  runtime_update_complete=true
  log "Bumpster updated to version $runtime_release_version."
  log "Previous installation backup: $runtime_previous_home"
)

# Function to check repository status
check_status() {
  local current_branch=""
  local effective_develop_branch="${develop_branch:-$default_develop_branch}"
  local effective_master_branch="${master_branch:-$default_master_branch}"
  local worktree_status=""
  local uncommitted_count=0
  local upstream_branch=""
  local unpushed_count=""

  require_git_repository
  current_branch="$(git rev-parse --abbrev-ref HEAD)" ||
    abort "Could not determine the current branch."
  log "Current branch: $current_branch"

  if [[ "$current_branch" == "HEAD" ]]; then
    log "You are in detached HEAD state."
  elif [[ "$current_branch" == "$effective_develop_branch" ]]; then
    log "You are on the development branch. Ready for new features."
  elif [[ "$current_branch" == "$effective_master_branch" ]]; then
    log "You are on the release branch. Only releases should be here."
  else
    log "You are on a feature branch. Merge your changes into the development branch when ready."
  fi

  worktree_status="$(git status --porcelain)" ||
    abort "Could not inspect the working tree."
  if [[ -n "$worktree_status" ]]; then
    while IFS= read -r; do
      uncommitted_count=$((uncommitted_count + 1))
    done <<< "$worktree_status"
  fi
  log "Uncommitted changes: $uncommitted_count"

  if [[ "$current_branch" != "HEAD" ]] &&
    upstream_branch="$(
      git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
    )"; then
    if unpushed_count="$(
      git rev-list --count "$upstream_branch..HEAD" 2>/dev/null
    )"; then
      log "Unpushed commits: $unpushed_count"
    else
      log "Unpushed commits: unavailable (could not compare with '$upstream_branch')."
    fi
  else
    log "Unpushed commits: unavailable (no upstream branch)."
  fi
}

# Function to show usage and version information
usage() {
  local local_version
  local version_info

  if [ -f "$logo_file" ]; then
    cat "$logo_file"
  else
    echo "Bumpster"
  fi

  local_version=$(display_version)
  version_info="$local_version"

  cat <<EOS
Bumpster $version_info
Usage:  bumpster [action]
        Run without an action to select a release type interactively.
        Choose only one action per invocation.

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
  GIT_MASTER_BRANCH                   Name of the release branch (default: main)
  GIT_DEVELOP_BRANCH                  Name of the development branch (default: dev)
  ENABLE_LOGGING                      Enable or disable logging (default: false)
  LOG_FILE                            Path to the log file (default: bumpster.log)
  DELETE_FEATURE_BRANCH_AFTER_MERGE   Automatically delete feature branches after merge (default: false)
  ASK_BEFORE_DELETING_FEATURE_BRANCH  Ask before deleting feature branches (default: true)
  SYNC_WITH_PACKAGE_JSON              Synchronize VERSION file with package.json (default: false)
  AFTER_BUMP_BRANCH                   Branch to return to (default: configured development branch)
  BEFORE_BUMP_BRANCH                  Required release start branch (default: configured development branch)
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
  local current_branch=""

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
    current_branch="$(git branch --show-current)" ||
      abort "Failed to determine the current branch."
    if [[ "$current_branch" == "$branch_name" ]]; then
      log "Already on branch '$branch_name'."
    else
      log "Switching to branch '$branch_name'."
      git checkout "$branch_name" ||
        abort "Failed to switch to branch '$branch_name'."
    fi
  fi
}

# Function to calculate a semantic version without changing repository state
calculate_next_version() {
  local source_version="$1"
  local requested_type="$2"
  local major
  local minor
  local patch

  IFS='.' read -r major minor patch <<< "$source_version"
  case "$requested_type" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# Function to calculate and validate a release plan before local mutations
prepare_release_plan() {
  local requested_type="${1:-}"
  local required_before_branch=""
  local worktree_status=""

  require_git_repository
  worktree_status="$(git status --porcelain)" ||
    abort "Could not inspect the working tree."
  if [[ -n "$worktree_status" ]]; then
    abort "Working tree contains unstaged changes. Aborting."
  fi

  release_develop_branch="${develop_branch:-$default_develop_branch}"
  release_master_branch="${master_branch:-$default_master_branch}"
  required_before_branch="${before_bump_branch:-$release_develop_branch}"
  if [[ -z "$required_before_branch" ]]; then
    required_before_branch="$release_develop_branch"
  fi
  if ! git show-ref --verify --quiet "refs/heads/$required_before_branch"; then
    abort "Configured BEFORE_BUMP_BRANCH '$required_before_branch' does not exist. Please create it or update your configuration."
  fi

  release_start_branch="$(git rev-parse --abbrev-ref HEAD)" ||
    abort "Could not determine the current branch."
  if [[ "$release_start_branch" != "$required_before_branch" ]]; then
    abort "Version bumps must be run from '$required_before_branch' (current branch: '$release_start_branch')."
  fi
  if [[ "$release_start_branch" == "$release_master_branch" ]]; then
    abort "BEFORE_BUMP_BRANCH must not be the configured release branch '$release_master_branch'."
  fi

  default_dev_branch="$release_develop_branch"
  default_master_branch="$release_master_branch"
  export default_dev_branch
  export default_master_branch

  if [[ ! -f "VERSION" ]]; then
    abort "VERSION file not found. Create it with a semantic version such as 0.1.0 before releasing."
  fi
  release_current_version="$(cat VERSION)" ||
    abort "Failed to read the VERSION file."
  if [[ ! "$release_current_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    abort "VERSION must contain MAJOR.MINOR.PATCH with no prefix, suffix, or leading zeros."
  fi
  log_highlighted \
    "Current version is $release_current_version" \
    "$release_current_version"

  release_version_type="$requested_type"
  if [[ -z "$release_version_type" ]]; then
    read -r -p \
      "Which version do you want to bump (major/minor/patch)? [patch]: " \
      release_version_type
    release_version_type="${release_version_type:-patch}"
  fi
  case "$release_version_type" in
    major | minor | patch) ;;
    *)
      abort "Invalid version type. Please choose between 'major', 'minor', or 'patch'."
      ;;
  esac

  release_new_version="$(
    calculate_next_version "$release_current_version" "$release_version_type"
  )" || abort "Could not calculate the next semantic version."
  if [[ "$release_current_version" == "$release_new_version" ]]; then
    abort "New version is the same as the current version."
  fi

  release_after_branch="${after_bump_branch:-$release_develop_branch}"
  if ! git show-ref --verify --quiet "refs/heads/$release_after_branch"; then
    log "Branch '$release_after_branch' does not exist. Falling back to development branch '$release_develop_branch'."
    release_after_branch="$release_develop_branch"
  fi

  if [[ "${sync_with_package_json}" == "true" && -f "package.json" ]]; then
    validate_package_json_for_sync "package.json" ||
      abort "package.json cannot be synchronized safely."
  fi

  preflight_release \
    "$release_new_version" \
    "$release_develop_branch" \
    "$release_master_branch"

  export BUMPSTER_PREV_VERSION="$release_current_version"
  export BUMPSTER_NEW_VERSION="$release_new_version"
  log_highlighted \
    "Release plan: $release_current_version -> $release_new_version ($release_version_type)." \
    "$release_current_version" \
    "$release_new_version" \
    "$release_version_type"
  log "Release branches: start '$release_start_branch', development '$release_develop_branch', release '$release_master_branch', return '$release_after_branch'."
}

# Function to update and stage files described by the prepared release plan
stage_release_files() {
  release_stage="updating VERSION"
  printf '%s' "$release_new_version" > VERSION ||
    abort "Failed to write version $release_new_version to VERSION."
  git add VERSION || abort "Failed to stage VERSION."

  if [[ "${sync_with_package_json}" == "true" ]]; then
    release_stage="synchronizing package.json"
    if [[ -f "package.json" ]]; then
      log "Synchronizing version with package.json."
      update_package_json_version "package.json" "$release_new_version" ||
        abort "Failed to update the root package.json version safely."
      git add package.json || abort "Failed to stage package.json."
      log_highlighted \
        "Updated version in package.json to $release_new_version." \
        "$release_new_version"
    else
      log "package.json not found. Skipping synchronization."
    fi
  fi
}

# Function to create the version commit described by the prepared release plan
commit_release_version() {
  release_stage="creating the version commit"
  git commit \
    -m "bump version to $release_new_version" \
    -m "Automatic version bump to $release_new_version" ||
    abort "Failed to create the version commit."
  log_highlighted \
    "Created version commit for $release_new_version." \
    "$release_new_version"
}

# Function to merge the prepared release branches and create the local tag
create_release_refs() {
  release_stage="preparing the development branch"
  check_or_create_branch "$release_develop_branch"

  if [[ "$release_start_branch" != "$release_develop_branch" ]]; then
    release_stage="merging into the development branch"
    log "Merging '$release_start_branch' into '$release_develop_branch'."
    git merge "$release_start_branch" --no-edit ||
      abort "Failed to merge '$release_start_branch' into '$release_develop_branch'."
  fi

  release_stage="preparing the release branch"
  check_or_create_branch "$release_master_branch"

  release_stage="merging the development branch into the release branch"
  log "Merging '$release_develop_branch' into '$release_master_branch'."
  git merge "$release_develop_branch" --no-edit ||
    abort "Failed to merge '$release_develop_branch' into '$release_master_branch'."

  release_stage="creating the release tag"
  git tag -a "v$release_new_version" -m "Release $release_new_version" ||
    abort "Failed to create release tag 'v$release_new_version'."
}

# Function to publish all prepared release refs as one remote transaction
publish_release_refs() {
  release_stage="atomic publication"
  log_highlighted \
    "Publishing '$release_develop_branch', '$release_master_branch', and tag 'v$release_new_version' atomically." \
    "v$release_new_version"
  git push --atomic origin \
    "$release_develop_branch" \
    "$release_master_branch" \
    "refs/tags/v$release_new_version" ||
    abort "Failed to publish the release atomically. Verify local and remote refs before recovery."

  release_published="true"
  release_stage="configuring branch upstreams"
  git branch \
    --set-upstream-to="origin/$release_develop_branch" \
    "$release_develop_branch" >/dev/null 2>&1 ||
    log "Could not configure upstream for '$release_develop_branch'." "WARN"
  git branch \
    --set-upstream-to="origin/$release_master_branch" \
    "$release_master_branch" >/dev/null 2>&1 ||
    log "Could not configure upstream for '$release_master_branch'." "WARN"
  log "Release branches and tag published successfully."
}

# Function to return to the configured branch after publication
return_to_after_bump_branch() {
  local current_branch=""

  release_stage="switching to the after-bump branch after publication"
  if ! git show-ref --verify --quiet "refs/heads/$release_after_branch"; then
    log "Branch '$release_after_branch' no longer exists. Falling back to '$release_develop_branch'."
    release_after_branch="$release_develop_branch"
  fi

  current_branch="$(git branch --show-current)" ||
    abort "Could not determine the current branch after publication."
  if [[ "$current_branch" == "$release_after_branch" ]]; then
    log "Release finished on branch '$release_after_branch'."
  else
    log "Returning to branch '$release_after_branch'."
    git checkout "$release_after_branch" ||
      abort "Failed to switch to branch '$release_after_branch'."
  fi
}

# Function to execute one fully validated release plan
execute_release_plan() {
  release_diagnostics_active="true"
  release_published="false"
  release_stage="starting local release mutations"
  release_tag_name="v$release_new_version"
  trap 'release_exit_handler "$?"' EXIT

  stage_release_files
  commit_release_version
  create_release_refs
  publish_release_refs
  return_to_after_bump_branch

  release_stage="post-bump hook"
  run_hook "post-bump"

  release_diagnostics_active="false"
  trap - EXIT
}

# Function to prepare and execute one release
run_release() {
  local requested_type="${1:-}"

  if [[ -z "${BASH_VERSION:-}" ]]; then
    abort "Bash is required to run this script."
  fi

  prepare_release_plan "$requested_type"
  run_hook "pre-bump"
  execute_release_plan
}

# Function to create a feature branch from the current dev branch
create_feature() {
  # Use the configured develop branch or fall back to default_develop_branch
  local dev_branch="${develop_branch:-$default_develop_branch}"
  local current_branch=""

  require_git_repository

  # Ensure the current branch is dev
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" ||
    abort "Could not determine the current branch."
  if [[ "$current_branch" == "HEAD" ]]; then
    abort "Cannot create a feature branch from detached HEAD."
  fi
  if [[ "$current_branch" != "$dev_branch" ]]; then
    abort "You are not on the development branch ('$dev_branch'). Switch to it before creating a feature branch."
  fi

  # Prompt for the feature branch name
  local feature_branch_name
  while true; do
    read -r -p "Enter the name for the new feature branch: " feature_branch_name ||
      abort "Feature branch name input ended before a valid name was provided."
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

# Delete one merged feature branch locally and, when possible, on origin.
delete_merged_feature_branch() {
  local feature_branch_name="$1"
  local dev_branch="$2"
  local unmerged_commits=""
  local remote_refs=""

  unmerged_commits="$(
    git log --format='%H' "$feature_branch_name" --not "$dev_branch"
  )" || abort "Could not verify whether feature branch '$feature_branch_name' is fully merged."
  if [[ -n "$unmerged_commits" ]]; then
    abort "Feature branch '$feature_branch_name' contains commits not merged into '$dev_branch'."
  fi

  log "Attempting to delete feature branch '$feature_branch_name'."
  git branch -d "$feature_branch_name" ||
    abort "Failed to delete branch '$feature_branch_name'."
  log "Local feature branch '$feature_branch_name' deleted."

  if ! remote_refs="$(
    git ls-remote origin "refs/heads/$feature_branch_name" 2>/dev/null
  )"; then
    log "Could not determine whether remote branch '$feature_branch_name' exists. Remote state was not changed." "WARN"
    return 0
  fi
  if [[ -z "$remote_refs" ]]; then
    log "Remote branch '$feature_branch_name' does not exist. Skipping remote deletion."
    return 0
  fi

  if git push origin --delete "$feature_branch_name"; then
    log "Remote branch '$feature_branch_name' deleted."
  else
    log "Failed to delete remote branch '$feature_branch_name'." "WARN"
  fi
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
  local branch_check=""
  local worktree_status=""

  require_git_repository
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
  worktree_status="$(git status --porcelain)" ||
    abort "Could not inspect the working tree."
  if [[ -n "$worktree_status" ]]; then
    log "You have uncommitted changes in your working directory."
    if ! read -r -p \
      "Stash them and restore them on '$dev_branch' after the merge? (y/n): " \
      stash_response; then
      abort "Feature closing confirmation ended before a response was provided."
    fi
    if [[ "$stash_response" =~ ^(y|Y|yes|Yes)$ ]]; then
      stash_before="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
      git stash push --include-untracked -m "Bumpster close-feature: $current_branch" ||
        abort "Failed to stash feature changes."
      created_stash_oid="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
      if [[ -z "$created_stash_oid" || "$created_stash_oid" == "$stash_before" ]]; then
        abort "Git did not create a new stash for the feature changes."
      fi
      worktree_status="$(git status --porcelain)" ||
        abort_close_feature "Could not verify the working tree after stashing." \
          "$created_stash_oid" "$current_branch"
      if [[ -n "$worktree_status" ]]; then
        abort_close_feature \
          "Some working tree changes could not be stashed. Feature closing was not started." \
          "$created_stash_oid" "$current_branch"
      fi
      log "Feature changes stashed as '$created_stash_oid'."
    else
      abort "Feature closing requires a clean working tree. Commit or stash the changes and retry."
    fi
  fi

  branch_check="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" ||
    abort_close_feature "Could not verify the current branch before closing the feature." \
      "$created_stash_oid" "$current_branch"
  if [[ "$branch_check" != "$current_branch" ]]; then
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
      if ! read -r -p \
        "Do you want to delete the feature branch '$current_branch'? (y/n): " \
        delete_response; then
        abort "Feature branch deletion confirmation ended before a response was provided."
      fi
      if [[ "$delete_response" =~ ^(y|Y|yes|Yes)$ ]]; then
        delete_merged_feature_branch "$current_branch" "$dev_branch"
      else
        log "Feature branch '$current_branch' retained."
      fi
    else
      delete_merged_feature_branch "$current_branch" "$dev_branch"
    fi
  else
    log "Feature branch '$current_branch' retained."
  fi

  # Reminder about uncommitted changes
  worktree_status="$(git status --porcelain)" || {
    log "Could not inspect the final working tree state." "WARN"
    return 0
  }
  if [[ -n "$worktree_status" ]]; then
    log "Reminder: You have uncommitted changes in your working directory. Please commit or stash them as needed."
  fi
}
