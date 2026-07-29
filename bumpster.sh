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

select_cli_command() {
  local command_name="$1"
  local option_name="$2"

  if [[ -n "$selected_command" ]]; then
    printf "Only one action option can be used at a time: '%s' and '%s'.\n" \
      "$selected_option" "$option_name" >&2
    usage 1
  fi

  selected_command="$command_name"
  selected_option="$option_name"
}

# Process command-line options
version_type=""
selected_command=""
selected_option=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      select_cli_command "help" "$1"
      ;;
    -v | --version)
      select_cli_command "version" "$1"
      ;;
    -M | --major)
      select_cli_command "release" "$1"
      version_type="major"
      ;;
    -m | --minor)
      select_cli_command "release" "$1"
      version_type="minor"
      ;;
    -p | --patch)
      select_cli_command "release" "$1"
      version_type="patch"
      ;;
    -u | --update)
      select_cli_command "update" "$1"
      ;;
    -s | --status)
      select_cli_command "status" "$1"
      ;;
    -l | --create-local-config)
      select_cli_command "create-local-config" "$1"
      ;;
    -f | --create-feature)
      select_cli_command "create-feature" "$1"
      ;;
    -c | --close-feature)
      select_cli_command "close-feature" "$1"
      ;;
    *)                              printf "Unknown option: '%s'\n" "$1" >&2
    usage 1 ;;
  esac
  shift
done

case "$selected_command" in
  help)
    usage
    ;;
  version)
    printf 'Bumpster version: %s\n' "$(display_version)"
    exit 0
    ;;
  update)
    run_update_command
    exit $?
    ;;
esac

# Preload configuration for commands that depend on configured branch names
case "$selected_command" in
  status | create-feature | close-feature)
    if [ -f "$local_config_file" ]; then
      load_config "$local_config_file"
    elif [ -f "$global_config_file" ]; then
      load_config "$global_config_file"
    fi
    ;;
esac

case "$selected_command" in
  status)
    check_status
    exit $?
    ;;
  close-feature)
    close_feature
    exit 0
    ;;
  create-feature)
    create_feature
    exit 0
    ;;
  create-local-config)
    create_local_config_file
    exit 0
    ;;
esac

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
