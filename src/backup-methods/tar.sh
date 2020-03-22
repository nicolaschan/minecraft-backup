#!/bin/env bash

# Backup to (compressed) tar archives, and automatically delete

OPTIND=1
while getopts 'a:d:e:f:i:l:m:o:' FLAG; do
  case $FLAG in
    a) COMPRESSION_ALGORITHM=$OPTARG ;;
    d) DELETE_METHOD=$OPTARG ;;
    e) COMPRESSION_FILE_EXTENSION=$OPTARG ;;
    f) TIMESTAMP=$OPTARG ;;
    i) SERVER_WORLD=$OPTARG ;;
    l) COMPRESSION_LEVEL=$OPTARG ;;
    m) MAX_BACKUPS=$OPTARG ;;
    o) BACKUP_DIRECTORY=$OPTARG ;;
    *) ;;
  esac
done

ARCHIVE_FILE_NAME=$TIMESTAMP.tar$COMPRESSION_FILE_EXTENSION
ARCHIVE_PATH=$BACKUP_DIRECTORY/$ARCHIVE_FILE_NAME
mkdir -p "$BACKUP_DIRECTORY"

# Parse file timestamp to one readable by "date"
parse-file-timestamp () {
  echo "$1" | awk -F_ '{gsub(/-/,":",$2); print $1" "$2}'
}

# Delete a backup
delete-backup () {
  local BACKUP=$1
  rm -f "$BACKUP_DIRECTORY/$BACKUP"
  echo "Deleted old backup" "$BACKUP"
}

# Sequential delete method
delete-sequentially () {
  local BACKUPS_UNSORTED_RAW=("$BACKUP_DIRECTORY"/*)
  local BACKUPS_UNSORTED=()
  for BACKUP_NAME in "${BACKUPS_UNSORTED_RAW[@]}"; do
    local BASENAME
    BASENAME=$(basename "$BACKUP_NAME")
    BACKUPS_UNSORTED+=("$BASENAME")
  done
  # List oldest first
  # shellcheck disable=SC2207
  IFS=$'\n' BACKUPS=($(sort <<<"${BACKUPS_UNSORTED[*]}"))

  while [[ $MAX_BACKUPS -ge 0 && ${#BACKUPS[@]} -gt $MAX_BACKUPS ]]; do
    delete-backup "${BACKUPS[0]}"
    local BACKUPS_UNSORTED_RAW=("$BACKUP_DIRECTORY"/*)
    local BACKUPS_UNSORTED=()
    for BACKUP_NAME in "${BACKUPS_UNSORTED_RAW[@]}"; do
      local BASENAME
      BASENAME=$(basename "$BACKUP_NAME")
      BACKUPS_UNSORTED+=("$BASENAME")
    done
    # List oldest first
    # shellcheck disable=SC2207
    IFS=$'\n' BACKUPS=($(sort <<<"${BACKUPS_UNSORTED[*]}"))
  done
}

# Functions to sort backups into correct categories based on timestamps
is-hourly-backup () {
  local TIMESTAMP=$*
  local MINUTE
  MINUTE=$(date -d "$TIMESTAMP" +%M)
  return "$MINUTE"
}
is-daily-backup () {
  local TIMESTAMP=$*
  local HOUR
  HOUR=$(date -d "$TIMESTAMP" +%H)
  return "$HOUR"
}
is-weekly-backup () {
  local TIMESTAMP=$*
  local DAY
  DAY=$(date -d "$TIMESTAMP" +%u)
  return $((DAY - 1))
}

# Helper function to sum an array
array-sum () {
  SUM=0
  for NUMBER in "$@"; do
    (( SUM += NUMBER ))
  done
  echo $SUM
}

# Thinning delete method
delete-thinning () {
  # sub-hourly, hourly, daily, weekly is everything else
  local BLOCK_SIZES=(16 24 30)
  # First block is unconditional
  # The next blocks will only accept files whose names cause these functions to return true (0)
  local BLOCK_FUNCTIONS=("is-hourly-backup" "is-daily-backup" "is-weekly-backup")

  # Warn if $MAX_BACKUPS does not have enough room for all the blocks
  TOTAL_BLOCK_SIZE=$(array-sum "${BLOCK_SIZES[@]}")
  if [[ $TOTAL_BLOCK_SIZE -gt $MAX_BACKUPS ]]; then
    log-warning "MAX_BACKUPS ($MAX_BACKUPS) is smaller than TOTAL_BLOCK_SIZE ($TOTAL_BLOCK_SIZE)"
  fi

  local CURRENT_INDEX=0

  local BACKUPS_UNSORTED_RAW=("$BACKUP_DIRECTORY"/*)
  local BACKUPS_UNSORTED=()
  for BACKUP_NAME in "${BACKUPS_UNSORTED_RAW[@]}"; do
    local BASENAME
    BASENAME=$(basename "$BACKUP_NAME")
    BACKUPS_UNSORTED+=("$BASENAME")
  done
  # List newest first
  # shellcheck disable=SC2207
  IFS=$'\n' BACKUPS=($(sort -r <<<"${BACKUPS_UNSORTED[*]}"))

  for BLOCK_INDEX in "${!BLOCK_SIZES[@]}"; do
    local BLOCK_SIZE=${BLOCK_SIZES[BLOCK_INDEX]}
    local BLOCK_FUNCTION=${BLOCK_FUNCTIONS[BLOCK_INDEX]}
    local OLDEST_BACKUP_IN_BLOCK_INDEX=$((BLOCK_SIZE + CURRENT_INDEX)) # Not an off-by-one error because a new backup was already saved 
    local OLDEST_BACKUP_IN_BLOCK=${BACKUPS[OLDEST_BACKUP_IN_BLOCK_INDEX]}

    if [[ $OLDEST_BACKUP_IN_BLOCK == "" ]]; then
      break
    fi

    local OLDEST_BACKUP_TIMESTAMP
    OLDEST_BACKUP_TIMESTAMP=$(parse-file-timestamp "${OLDEST_BACKUP_IN_BLOCK:0:19}")

   if ! $BLOCK_FUNCTION "$OLDEST_BACKUP_TIMESTAMP"; then
      # Oldest backup in this block does not satisfy the condition for placement in next block
      delete-backup "$OLDEST_BACKUP_IN_BLOCK"
      break
    fi

    ((CURRENT_INDEX += BLOCK_SIZE))
  done

  delete-sequentially
}


clean-up () {
  # Re-enable world autosaving
  execute-command "save-on"

  # Save the world
  execute-command "save-all"
}

minecraft-backup-backup () {
  case $COMPRESSION_ALGORITHM in
    "") # No compression
      tar -cf "$ARCHIVE_PATH" -C "$SERVER_WORLD" .
      ;;
    *) # With compression
      tar -cf - -C "$SERVER_WORLD" . | $COMPRESSION_ALGORITHM -cv -"$COMPRESSION_LEVEL" - > "$ARCHIVE_PATH" 2>> /dev/null
      ;;
  esac
  sync
}

minecraft-backup-check () {
  WORLD_SIZE_BYTES=$(du -b --max-depth=0 "$SERVER_WORLD" | awk '{print $1}')
  ARCHIVE_SIZE_BYTES=$(du -b "$ARCHIVE_PATH" | awk '{print $1}')
  BACKUP_DIRECTORY_SIZE=$(du -h --max-depth=0 "$BACKUP_DIRECTORY" | awk '{print $1}')

  ARCHIVE_SIZE=$(numfmt --to=iec "$ARCHIVE_SIZE_BYTES")
  COMPRESSION_PERCENT=$((ARCHIVE_SIZE_BYTES * 100 / WORLD_SIZE_BYTES))
  # Check that archive size is not null and at least 1024 KB
  if [[ "$ARCHIVE_SIZE" != "" && "$ARCHIVE_SIZE_BYTES" -gt 8 ]]; then
    echo "$ARCHIVE_SIZE/$BACKUP_DIRECTORY_SIZE, $COMPRESSION_PERCENT%"
  else
    return 1
  fi
}

minecraft-backup-epilog () {
  case $DELETE_METHOD in
    "sequential") delete-sequentially
      ;;
    "thin") delete-thinning
      ;;
  esac
}
