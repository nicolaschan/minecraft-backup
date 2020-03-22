#!/bin/env bash

# Backup to restic

OPTIND=1
while getopts 'i:o:' FLAG; do
  case $FLAG in
    i) SERVER_WORLD=$OPTARG ;;
    o) RESTIC_REPO=$OPTARG ;;
    *) ;;
  esac
done

minecraft-backup-backup () {
  restic backup -r "$RESTIC_REPO" "$SERVER_WORLD"
}

minecraft-backup-check () {
  local WORLD_SIZE_BYTES
  WORLD_SIZE_BYTES=$(du -b --max-depth=0 "$SERVER_WORLD" | awk '{print $1}')
  echo "$WORLD_SIZE_BYTES"
}

minecraft-backup-epilog () {
  # do nothing
  echo -n
}
