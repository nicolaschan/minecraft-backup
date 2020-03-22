#!/usr/bin/env bash

# Execute commands on a Minecraft server running in a GNU screen

OPTIND=1
while getopts 's:' FLAG "$@"; do
  case $FLAG in
    s) SCREEN_NAME=$OPTARG ;;
    *) ;;
  esac
done

minecraft-backup-execute () {
    local COMMAND=$1
    if ! screen -S "$SCREEN_NAME" -Q "select" .; then
        return 1
    fi
    if [[ "$SCREEN_NAME" != "" ]]; then
        screen -S "$SCREEN_NAME" -p 0 -X stuff "$COMMAND$(printf \\r)"
    fi
}
