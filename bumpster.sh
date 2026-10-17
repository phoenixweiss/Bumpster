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
selected_package=""
version_source=""
version_type=""
selected_command=""
selected_option=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version-source)
      [[ -z "$version_source" && $# -ge 2 ]] ||
        abort "--version-source requires exactly one source."
      case "$2" in
        version-file | package-json | tag:?*) version_source="$2" ;;
        *) abort "--version-source expects version-file, package-json, or tag:NAME." ;;
      esac
      shift
      ;;
    --package)
      [[ -z "$selected_package" && $# -ge 2 && "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
        abort "--package requires one package key (letters, digits, underscore, hyphen)."
      selected_package="$2"
      shift
      ;;
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
    -x | --create-hotfix)
      select_cli_command "create-hotfix" "$1"
      ;;
    -H | --hotfix)
      select_cli_command "release" "$1"
      version_type="hotfix"
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

if [[ -n "$version_source" ]]; then
  case "$selected_command" in
    "" | release) ;;
    *) abort "--version-source is supported only for releases." ;;
  esac
fi

if [[ -n "$selected_package" ]]; then
  case "$selected_command" in
    "" | release | status) ;;
    *) abort "--package is supported only for releases and --status." ;;
  esac
fi

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
  status | create-feature | close-feature | create-hotfix)
    if [ -f "$local_config_file" ]; then
      load_config "$local_config_file"
    elif [ -f "$global_config_file" ]; then
      load_config "$global_config_file"
    fi
    ;;
esac

case "$selected_command" in
  status)
    resolve_release_target
    check_status || exit $?
    report_version_sources
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
  create-hotfix)
    create_hotfix
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
elif [[ -n "$selected_package" ]]; then
  log "No branch configuration found. Using default branches for the selected package."
else
  log "No branch configuration found. Using default branches without creating configuration."
fi

resolve_release_target

# Prepare the complete release plan before the first local mutation, then run it
run_release "$version_type"
