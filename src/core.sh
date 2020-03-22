#!/usr/bin/env bash

# This script implements the core functionality, and expects the following
# functions to be defined by the method scripts:
#
# minecraft-backup-execute "$COMMAND"
#   where $COMMAND is a command sent to the Minecraft server console
# minecraft-backup-backup
#   which performs a backup
# minecraft-backup-check
# minecraft-backup-epilog

# Default Configuration
EXECUTE_METHOD="$1"
shift
EXECUTE_METHOD_OPTIONS=()
while [[ $1 != "--" ]]; do
  EXECUTE_METHOD_OPTIONS+=("$1")
  shift
done
shift
BACKUP_METHOD="$1"
shift
BACKUP_METHOD_OPTIONS=()
while [[ $1 != "--" ]]; do
  BACKUP_METHOD_OPTIONS+=("$1")
  shift
done
shift

OPTIND=1
while getopts 'c:g:p:q:v:' FLAG; do
  case $FLAG in
    c) ENABLE_CHAT_MESSAGES=$OPTARG ;;
    g) EXIT_IF_NO_SCREEN=$OPTARG ;;
    p) PREFIX=$OPTARG ;;
    q) SUPPRESS_WARNINGS=$OPTARG ;;
    v) DEBUG=$OPTARG ;;
    *) ;;
  esac
done

BASE_DIR=$(dirname "$(realpath "$0")")

# shellcheck source=logging.sh
source "$BASE_DIR/logging.sh" \
  -q "$SUPPRESS_WARNINGS" \
  -v "$DEBUG"

EXECUTE_METHOD_PATH=$EXECUTE_METHOD
BACKUP_METHOD_PATH=$BACKUP_METHOD

assert-all () {
  local TEST_CMD=$1
  local MESSAGE=$2
  shift 2
  local ITEMS=("$@")

  local RESULT=true
  for ITEM in "${ITEMS[@]}"; do
    if ! $TEST_CMD "$ITEM"; then
      log-fatal "$MESSAGE $ITEM"
      RESULT=false
    fi
  done
  if ! $RESULT; then
    exit 1
  fi
}

assert-files-exist () {
  assert-all "test -f" "Script not found:" "$@"
}

assert-files-exist \
  "$EXECUTE_METHOD_PATH" \
  "$BACKUP_METHOD_PATH"

# shellcheck source=exec-methods/screen.sh
source "$EXECUTE_METHOD_PATH" "${EXECUTE_METHOD_OPTIONS[@]}"

# shellcheck source=backup-methods/tar.sh
source "$BACKUP_METHOD_PATH" "${BACKUP_METHOD_OPTIONS[@]}"

# fn_exists based upon https://stackoverflow.com/q/85880
fn_exists () {
    LC_ALL=C type "$1" 2>&1 | grep -q 'function'
}
assert-functions-exist () {
  assert-all fn_exists "Function not defined:" "$@"
}

assert-functions-exist \
  minecraft-backup-execute \
  minecraft-backup-backup \
  minecraft-backup-check \
  minecraft-backup-epilog

# Minecraft server communication interface functions
execute-command () {
  minecraft-backup-execute "$@"
}
message-players () {
  message-players-color "gray" "$@"
}
message-players-error () {
  message-players-color "red" "$@"
}
message-players-warning () {
  message-players-color "yellow" "$@"
}
message-players-success () {
  message-players-color "green" "$@"
}
message-players-color () {
  local COLOR=$1
  local MESSAGE=$2
  local HOVER_MESSAGE=$3
  log-info "$MESSAGE ($HOVER_MESSAGE)"
  if $ENABLE_CHAT_MESSAGES; then
  execute-command \
    "tellraw @a [\"\",{\"text\":\"[$PREFIX] \",\"color\":\"gray\",\"italic\":true},{\"text\":\"$MESSAGE\",\"color\":\"$COLOR\",\"italic\":true,\"hoverEvent\":{\"action\":\"show_text\",\"value\":{\"text\":\"\",\"extra\":[{\"text\":\"$HOVER_MESSAGE\"}]}}}]"
  fi
}

clean-up () {
  # Re-enable world autosaving
  execute-command "save-on"

  # Save the world
  execute-command "save-all"
}

trap-ctrl-c () {
  log-warning "Backup interrupted. Attempting to re-enable autosaving"
  clean-up
  exit 2
}

trap "trap-ctrl-c" 2

# Notify players of start
message-players "Starting backup..." "$TIMESTAMP"

# Disable world autosaving
execute-command "save-off"
RESULT=$?
if $EXIT_IF_NO_SCREEN && [[ $RESULT != "0" ]]; then
  exit $RESULT
fi

# Record start time for performance reporting
START_TIME=$(date +"%s")
minecraft-backup-backup
BACKUP_RESULT=$?
END_TIME=$(date +"%s")

clean-up 

TIME_DELTA=$((END_TIME - START_TIME))
CHECK_MESSAGE=$(minecraft-backup-check)
CHECK_RESULT=$?

if [[ $BACKUP_RESULT != "0" ]] || [[ $CHECK_RESULT != "0" ]]; then
  message-players-error "Backup failed!" "Please notify an admin."
  exit $CHECK_RESULT
fi

message-players-success "Backup complete!" "$TIME_DELTA s, $CHECK_MESSAGE"

EPILOG_MESSAGE=$(minecraft-backup-epilog)
EPILOG_RESULT=$?

if [[ $EPILOG_RESULT != "0" ]]; then
  message-players-warning "Backup epilog failed."
fi

if [[ $EPILOG_MESSAGE != "" ]]; then
  message-players "$EPILOG_MESSAGE"
fi
