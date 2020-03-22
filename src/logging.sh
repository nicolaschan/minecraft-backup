#!/usr/bin/env bash

SUPPRESS_WARNINGS=false
DEBUG=true

OPTIND=1
while getopts 'q:v:' FLAG; do
  case $FLAG in
    q) SUPPRESS_WARNINGS=$OPTARG ;;
    v) DEBUG=$OPTARG ;;
    *) ;;
  esac
done

echo-colored () {
  local COLOR_CODE="$1"
  shift
  local MESSAGE="$*"
  if test -t 1 && [ "$(tput colors)" -gt 1 ]; then
    # This terminal supports color
    echo -ne "\033[${COLOR_CODE}m${MESSAGE}\033[0m"
  else
    # Output does not support color
    echo -n "$MESSAGE"
  fi
}
log () {
  local COLOR="$1"
  local TYPE="$2"
  local MESSAGE="$3"
  echo-colored "$COLOR" "${TYPE}: "
  echo-colored "0" "$MESSAGE"
  echo
}
log-fatal () {
  >&2 log "0;31" "FATAL" "$*"
}
log-warning () {
  if ! $SUPPRESS_WARNINGS; then
    >&2 log "0;33" "WARNING" "$*"
  fi
}
log-info () {
  if $DEBUG; then
    log "0;36" "INFO" "$*"
  fi
}
