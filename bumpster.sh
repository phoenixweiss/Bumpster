#!/bin/bash

set -o pipefail

export LC_ALL=C.UTF-8

# Source configuration and function files
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/functions.sh"

run_update_command() {
  # BUMPSTER_HOME is initialized by the sourced config in the current shell.
  # shellcheck disable=SC2031
  local update_home="$BUMPSTER_HOME"

  # Replacing the CLI process releases Windows handles before the runtime rename.
  # The single-quoted script must expand variables only in the new Bash process.
  # shellcheck disable=SC2016,SC2093
  exec env BUMPSTER_HOME="$update_home" "$BASH" -c '
    runtime_home="$1"

    cd "$(dirname "$runtime_home")" || exit 1
    source "$runtime_home/config.sh" || exit 1
    source "$runtime_home/lib/functions.sh" || exit 1
    update_bumpster
  ' bumpster-update "$update_home"

  log "Could not start the isolated update process." "ERROR"
  return 1
}

# Process command-line options
version_type=""
create_local_config=""
create_feature_branch=""
close_feature_branch=""
show_status=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)                    usage ;;
    -v | --version)                 echo "Bumpster version: $(display_version)" ; exit 0 ;;
    -M | --major )                  version_type="major" ;;
    -m | --minor )                  version_type="minor" ;;
    -p | --patch )                  version_type="patch" ;;
    -u | --update )                 run_update_command ; exit $? ;;
    -s | --status )                 show_status="true" ;;
    -l | --create-local-config )    create_local_config="true" ;;
    -f | --create-feature )         create_feature_branch="true" ;;
    -c | --close-feature )          close_feature_branch="true" ;;
    *)                              printf "Unknown option: '%s'\n" "$1" >&2
    usage 1 ;;
  esac
  shift
done

# Preload configuration for commands that depend on configured branch names
if [[ "$close_feature_branch" == "true" ||
  "$create_feature_branch" == "true" ||
  "$show_status" == "true" ]]; then
  if [ -f "$local_config_file" ]; then
    load_config "$local_config_file"
  elif [ -f "$global_config_file" ]; then
    load_config "$global_config_file"
  fi
fi

# Show repository status if the option was passed
if [[ "$show_status" == "true" ]]; then
  check_status
  exit $?
fi

# Close a feature branch if the option was passed
if [[ "$close_feature_branch" == "true" ]]; then
  close_feature
  exit 0
fi

# Create a feature branch if the option was passed
if [[ "$create_feature_branch" == "true" ]]; then
  create_feature
  exit 0
fi

# Create local configuration file if the option was passed
if [[ "$create_local_config" == "true" ]]; then
  create_local_config_file
  exit 0
fi

# Check if either local or global config exists, load the local config first
if [ -f "$local_config_file" ]; then
  log "Using local configuration from '$local_config_file'."
  load_config "$local_config_file"
elif [ -f "$global_config_file" ]; then
  log "Using global configuration from '$global_config_file'."
  load_config "$global_config_file"
else
  log "No configuration file found."
  log "Running initial setup..."
  interactive_setup ||
    abort "Could not create global configuration file at '$global_config_file'."
fi

# Prepare the complete release plan before the first local mutation, then run it
run_release "$version_type"
