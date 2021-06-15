#!/usr/bin/env bash

# Minecraft server automatic backup management script
# https://github.com/nicolaschan/minecraft-backup
# MIT License
#
# For Minecraft servers running in a GNU screen, tmux, or RCON.
# For most convenience, run automatically with cron.

# Default Configuration 
SCREEN_NAME="" # Name of the GNU Screen, tmux session, or hostname:port:password for RCON
SERVER_WORLDS=() # Server world directory
BACKUP_DIRECTORY="" # Directory to save backups in
MAX_BACKUPS=128 # -1 indicates unlimited
DELETE_METHOD="thin" # Choices: thin, sequential, none; sequential: delete oldest; thin: keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
COMPRESSION_ALGORITHM="gzip" # Leave empty for no compression
COMPRESSION_FILE_EXTENSION=".gz" # Leave empty for no compression; Precede with a . (for example: ".gz")
COMPRESSION_LEVEL=3 # Passed to the compression algorithm
ENABLE_CHAT_MESSAGES=false # Tell players in Minecraft chat about backup status
PREFIX="Backup" # Shows in the chat message
DEBUG=false # Enable debug messages
SUPPRESS_WARNINGS=false # Suppress warnings
RESTIC_HOSTNAME="" # Leave empty to use system hostname
LOCK_FILE="" # Optional lock file to acquire to ensure two backups don't run at once
LOCK_FILE_TIMEOUT="" # Optional lock file wait timeout (in seconds)
WINDOW_MANAGER="screen" # Choices: screen, tmux, RCON

# Other Variables (do not modify)
DATE_FORMAT="%F_%H-%M-%S"
TIMESTAMP=$(date +$DATE_FORMAT)

log-fatal () {
  echo -e "\033[0;31mFATAL:\033[0m $*"
}
log-warning () {
  echo -e "\033[0;33mWARNING:\033[0m $*"
}
debug-log () {
  if "$DEBUG"; then
    echo "$1"
  fi
}

while getopts 'a:cd:e:f:hH:i:l:m:o:p:qr:s:t:u:vw:x' FLAG; do
  case $FLAG in
    a) COMPRESSION_ALGORITHM=$OPTARG ;;
    c) ENABLE_CHAT_MESSAGES=true ;;
    d) DELETE_METHOD=$OPTARG ;;
    e) COMPRESSION_FILE_EXTENSION=".$OPTARG" ;;
    f) TIMESTAMP=$OPTARG ;;
    h) echo "Minecraft Backup"
       echo "Repository: https://github.com/nicolaschan/minecraft-backup"
       echo "-a    Compression algorithm (default: gzip)"
       echo "-c    Enable chat messages"
       echo "-d    Delete method: thin (default), sequential, none"
       echo "-e    Compression file extension, exclude leading \".\" (default: gz)"
       echo "-f    Output file name (default is the timestamp)"
       echo "-h    Shows this help text"
       echo "-H    Set hostname for restic backup (restic only)"
       echo "-i    Input directory (path to world folder, use -i once for each world)"
       echo "-l    Compression level (default: 3)"
       echo "-m    Maximum backups to keep, use -1 for unlimited (default: 128)"
       echo "-o    Output directory"
       echo "-p    Prefix that shows in Minecraft chat (default: Backup)"
       echo "-q    Suppress warnings"
       echo "-r    Restic repo name (if using restic)"
       echo "-s    Screen name, tmux session name, or hostname:port:password for RCON"
       echo "-t    Enable lock file (lock file not used by default)"
       echo "-u    Lock file timeout seconds (empty = unlimited)"
       echo "-v    Verbose mode"
       echo "-w    Window manager: screen (default), tmux, RCON"
       exit 0
       ;;
    H) RESTIC_HOSTNAME=$OPTARG ;;
    i) SERVER_WORLDS+=("$OPTARG") ;;
    l) COMPRESSION_LEVEL=$OPTARG ;;
    m) MAX_BACKUPS=$OPTARG ;;
    o) BACKUP_DIRECTORY=$OPTARG ;;
    p) PREFIX=$OPTARG ;;
    q) SUPPRESS_WARNINGS=true ;;
    r) RESTIC_REPO=$OPTARG ;;
    s) SCREEN_NAME=$OPTARG ;;
    t) LOCK_FILE=$OPTARG ;;
    u) LOCK_FILE_TIMEOUT=$OPTARG ;;
    v) DEBUG=true ;;
    w) WINDOW_MANAGER=$OPTARG ;;
    *) log-fatal "Invalid option -$FLAG"; exit 1 ;;
  esac
done

rcon-command () {
  HOST="$(echo "$1" | cut -d: -f1)"
  PORT="$(echo "$1" | cut -d: -f2)"
  PASSWORD="$(echo "$1" | cut -d: -f3-)"
  COMMAND="$2"

  reverse-hex-endian () {
    # Given a 4-byte hex integer, reverse endianness
    while read -r -d '' -N 8 INTEGER; do
      echo "$INTEGER" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/'
    done
  }

  decode-hex-int () {
    # decode little-endian hex integer
    while read -r -d '' -N 8 INTEGER; do
      BIG_ENDIAN_HEX=$(echo "$INTEGER" | reverse-hex-endian)
      echo "$((16#$BIG_ENDIAN_HEX))"
    done
  }

  stream-to-hex () {
    xxd -ps
  }

  hex-to-stream () {
    xxd -ps -r
  }

  encode-int () {
    # Encode an integer as 4 bytes in little endian and return as hex
    INT="$1"
    # Source: https://stackoverflow.com/a/9955198
    printf "%08x" "$INT" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/' 
  }

  encode () {
    # Encode a packet type and payload for the rcon protocol
    TYPE="$1"
    PAYLOAD="$2"
    REQUEST_ID="$3"
    PAYLOAD_LENGTH="${#PAYLOAD}" 
    TOTAL_LENGTH="$((4 + 4 + PAYLOAD_LENGTH + 1 + 1))"

    OUTPUT=""
    OUTPUT+=$(encode-int "$TOTAL_LENGTH")
    OUTPUT+=$(encode-int "$REQUEST_ID")
    OUTPUT+=$(encode-int "$TYPE")
    OUTPUT+=$(echo -n "$PAYLOAD" | stream-to-hex)
    OUTPUT+="0000"
    
    echo -n "$OUTPUT" | hex-to-stream 
  }

  read-response () {
    # read next response packet and return the payload text
    HEX_LENGTH=$(head -c4 <&3 | stream-to-hex | reverse-hex-endian)
    LENGTH=$((16#$HEX_LENGTH))

    RESPONSE_PAYLOAD=$(head -c $LENGTH <&3 | stream-to-hex)
    echo -n "$RESPONSE_PAYLOAD"
  }

  response-request-id () {
    echo -n "${1:0:8}" | decode-hex-int
  }

  response-type () {
    echo -n "${1:8:8}" | decode-hex-int
  }

  response-payload () {
    echo -n "${1:16:-4}" | hex-to-stream
  }

  login () {
    PASSWORD="$1"
    encode 3 "$PASSWORD" 12 >&3

    RESPONSE=$(read-response "$IN_PIPE")

    RESPONSE_REQUEST_ID=$(response-request-id "$RESPONSE")
    if [[ "$RESPONSE_REQUEST_ID" == "-1" ]] || [[ "$RESPONSE_REQUEST_ID" == "4294967295" ]]; then
      log-warning "RCON connection failed: Wrong RCON password" 1>&2
      return 1
    fi
  }

  run-command () {
    COMMAND="$1"
    
    # encode 2 "$COMMAND" 13 >> "$OUT_PIPE"
    encode 2 "$COMMAND" 13 >&3

    RESPONSE=$(read-response "$IN_PIPE")
    response-payload "$RESPONSE"
  }

  # Open a TCP socket
  # Source: https://www.xmodulo.com/tcp-udp-socket-bash-shell.html
  if ! exec 3<>/dev/tcp/"$HOST"/"$PORT"; then
    log-warning "RCON connection failed: Could not connect to $HOST:$PORT"
    return 1
  fi

  login "$PASSWORD" || return 1
  debug-log "$(run-command "$COMMAND")"

  # Close the socket
  exec 3<&-
  exec 3>&-
}

if ! "$DEBUG"; then
  QUIET="-q"
else
  QUIET=""
fi

if [[ "$COMPRESSION_FILE_EXTENSION" == "." ]]; then
  COMPRESSION_FILE_EXTENSION=""
fi

# Check for missing encouraged arguments
if ! $SUPPRESS_WARNINGS; then
  if [[ "$SCREEN_NAME" == "" ]]; then
    log-warning "Minecraft screen/tmux/rcon location not specified (use -s)"
  fi
fi
# Check for required arguments
MISSING_CONFIGURATION=false
if [[ "${#SERVER_WORLDS[@]}" == "0" ]]; then
  log-fatal "Server world not specified (use -i)"
  MISSING_CONFIGURATION=true
fi
if [[ "$BACKUP_DIRECTORY" == "" ]] && [[ "$RESTIC_REPO" == "" ]]; then
  log-fatal "Backup location not specified (use -o or -r)"
  MISSING_CONFIGURATION=true
fi
if [[ "$RESTIC_REPO" != "" ]]; then
  if [[ "$BACKUP_DIRECTORY" != "" ]]; then
    log-fatal "Both output directory (-o) and restic repo (-r) specified but only one may be used at a time"
    MISSING_CONFIGURATION=true
  fi
  if [[ $MAX_BACKUPS -ge 0 ]] && [[ $MAX_BACKUPS -lt 70 ]] && [[ $DELETE_METHOD == "thin" ]]; then
    log-fatal "Thinning delete with restic requires at least 70 snapshots to be kept. If you need to keep fewer than 70, use sequential delete."
    MISSING_CONFIGURATION=true
  fi
fi

if $MISSING_CONFIGURATION; then
  exit 1
fi

if [[ "$BACKUP_DIRECTORY" != "" ]]; then
  ARCHIVE_FILE_NAME="$TIMESTAMP.tar$COMPRESSION_FILE_EXTENSION"
  ARCHIVE_PATH="$BACKUP_DIRECTORY/$ARCHIVE_FILE_NAME"
fi
if [[ "$RESTIC_REPO" != "" ]]; then
  ARCHIVE_PATH="$RESTIC_REPO $TIMESTAMP"
fi

# Minecraft server screen interface functions
message-players () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "gray"
}
execute-command () {
  local COMMAND=$1
  if [[ $SCREEN_NAME != "" ]]; then
    case $WINDOW_MANAGER in
      "screen") screen -S "$SCREEN_NAME" -p 0 -X stuff "$COMMAND$(printf \\r)"
        ;;
      "tmux") tmux send-keys -t "$SCREEN_NAME" "$COMMAND" ENTER
        ;;
      "RCON"|"rcon") rcon-command "$SCREEN_NAME" "$COMMAND"
        ;;
    esac
  fi
}
message-players-error () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "red"
}
message-players-success () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "green"
}
message-players-color () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  local COLOR=$3
  debug-log "$MESSAGE ($HOVER_MESSAGE)"
  if $ENABLE_CHAT_MESSAGES; then
    execute-command "tellraw @a [\"\",{\"text\":\"[$PREFIX] \",\"color\":\"gray\",\"italic\":true},{\"text\":\"$MESSAGE\",\"color\":\"$COLOR\",\"italic\":true,\"hoverEvent\":{\"action\":\"show_text\",\"value\":{\"text\":\"\",\"extra\":[{\"text\":\"$HOVER_MESSAGE\"}]}}}]"
  fi
}

# Parse file timestamp to one readable by "date" 
parse-file-timestamp () {
  local DATE_STRING
  DATE_STRING="$(echo "$1" | awk -F_ '{gsub(/-/,":",$2); print $1" "$2}')"
  echo "$DATE_STRING"
}

# Delete a backup
delete-backup () {
  local BACKUP=$1
  rm "$BACKUP_DIRECTORY"/"$BACKUP"
  message-players "Deleted old backup" "$BACKUP"
}

# Sequential delete method
delete-sequentially () {
  local BACKUPS=("$BACKUP_DIRECTORY"/*) # List oldest first
  while [[ $MAX_BACKUPS -ge 0 && ${#BACKUPS[@]} -gt $MAX_BACKUPS ]]; do
    delete-backup "$(basename "${BACKUPS[0]}")"
    BACKUPS=("$BACKUP_DIRECTORY"/*)
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
  return "$((DAY - 1))"
}

# Helper function to sum an array
array-sum () {
  SUM=0
  for NUMBER in "$@"; do
    (( SUM += NUMBER ))
  done
  echo "$SUM"
}

# Given two exit codes, print a nonzero one if there is one
exit-code () {
  if [[ "$1" != "0" ]]; then
    echo "$1"
  else
    if [[ "$2" == "" ]]; then
      echo 0
    else
      echo "$2"
    fi
  fi
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
  if [[  $MAX_BACKUPS != -1 ]] && [[ $TOTAL_BLOCK_SIZE -gt $MAX_BACKUPS ]]; then
    if ! $SUPPRESS_WARNINGS; then
      log-warning "MAX_BACKUPS ($MAX_BACKUPS) is smaller than TOTAL_BLOCK_SIZE ($TOTAL_BLOCK_SIZE)"
    fi
  fi

  local CURRENT_INDEX=0
  local BACKUPS=("$BACKUP_DIRECTORY"/*) # Oldest first
  local NUM_BACKUPS="${#BACKUPS[@]}"

  for BLOCK_INDEX in "${!BLOCK_SIZES[@]}"; do
    local BLOCK_SIZE=${BLOCK_SIZES[BLOCK_INDEX]}
    local BLOCK_FUNCTION=${BLOCK_FUNCTIONS[BLOCK_INDEX]}
    local OLDEST_BACKUP_IN_BLOCK_INDEX=$((NUM_BACKUPS - 1 - (BLOCK_SIZE + CURRENT_INDEX))) # Not an off-by-one error because a new backup was already saved 
    if [ "$OLDEST_BACKUP_IN_BLOCK_INDEX" -lt 0 ]; then
      break;
    fi
    local OLDEST_BACKUP_IN_BLOCK
    OLDEST_BACKUP_IN_BLOCK="$(basename "${BACKUPS[OLDEST_BACKUP_IN_BLOCK_INDEX]}")"

    local OLDEST_BACKUP_TIMESTAMP
    OLDEST_BACKUP_TIMESTAMP=$(parse-file-timestamp "${OLDEST_BACKUP_IN_BLOCK:0:19}")
    local BLOCK_COMMAND="$BLOCK_FUNCTION $OLDEST_BACKUP_TIMESTAMP"

   if $BLOCK_COMMAND; then
      # Oldest backup in this block satisfies the condition for placement in the next block
      debug-log "$OLDEST_BACKUP_IN_BLOCK promoted to next block" 
    else
      # Oldest backup in this block does not satisfy the condition for placement in next block
      delete-backup "$OLDEST_BACKUP_IN_BLOCK"
      break
    fi

    ((CURRENT_INDEX += BLOCK_SIZE))
  done

  delete-sequentially
}

delete-restic-sequential () {
  if [ "$MAX_BACKUPS" -ge 0 ]; then
    restic forget -r "$RESTIC_REPO" --keep-last "$MAX_BACKUPS" "$QUIET"
  fi
}

delete-restic-thinning () {
  if [ "$MAX_BACKUPS" -ge 70 ]; then 
    # MAX_BACKUPS >= 70
    restic forget -r "$RESTIC_REPO" --keep-last 16 --keep-hourly 24 --keep-daily 30 --keep-weekly $((MAX_BACKUPS - 70)) "$QUIET"
  else 
    # We have a check that MAX_BACKUPS is not 70 > MAX_BACKUPS >= 0, so we can assume here it is negative
    # Negative means don't delete old snapshots
    restic forget -r "$RESTIC_REPO" --keep-last 16 --keep-hourly 24 --keep-daily 30 --keep-weekly 9999999 "$QUIET"
  fi
}

# Delete old backups
delete-old-backups () {
  if [[ "$BACKUP_DIRECTORY" != "" ]]; then
    case $DELETE_METHOD in
      "sequential") delete-sequentially
        ;;
      "thin") delete-thinning
        ;;
    esac
  fi
  if [[ "$RESTIC_REPO" != "" ]]; then
    case $DELETE_METHOD in
      "sequential") delete-restic-sequential
        ;;
     "thin") delete-restic-thinning
        ;;
    esac
  fi
}

clean-up () {
  # Re-enable world autosaving
  execute-command "save-on"

  # Save the world
  execute-command "save-all"

  TIME_DELTA=$((END_TIME - START_TIME))

  if [[ "$BACKUP_DIRECTORY" != "" ]]; then
    WORLD_SIZE_BYTES=$(du --bytes --total --max-depth=0 "${SERVER_WORLDS[@]}" | tail -n 1 | awk '{print $1}')
    ARCHIVE_SIZE_BYTES=$(du -b "$ARCHIVE_PATH" | awk '{print $1}')
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | awk '{print $1}')
    BACKUP_DIRECTORY_SIZE=$(du -h --max-depth=0 "$BACKUP_DIRECTORY" | awk '{print $1}')

    # Check that archive size is not null and at least 200 Bytes
    if [[ "$ARCHIVE_EXIT_CODE" == "0" && "$WORLD_SIZE_BYTES" -gt 0 && "$ARCHIVE_SIZE" != "" && "$ARCHIVE_SIZE_BYTES" -gt 200 ]]; then
      # Notify players of completion
      COMPRESSION_PERCENT=$((ARCHIVE_SIZE_BYTES * 100 / WORLD_SIZE_BYTES))
      message-players-success "Backup complete!" "$TIME_DELTA s, $ARCHIVE_SIZE/$BACKUP_DIRECTORY_SIZE, $COMPRESSION_PERCENT%"
      delete-old-backups
      exit 0
    else
      rm "$ARCHIVE_PATH" # Delete bad archive so we can't fill up with bad archives
      message-players-error "Backup was not saved!" "Please notify an administrator"
      exit 1
    fi
  fi

  if [[ "$RESTIC_REPO" != "" ]]; then
    if [[ "$ARCHIVE_EXIT_CODE" == "0" ]]; then
      message-players-success "Backup complete!" "$TIME_DELTA s"
      delete-old-backups
      exit 0
    else
      message-players-error "Backup was not saved!" "Please notify an administrator"
      exit 1
    fi
  fi
}

trap "clean-up" 2

do-backup () {
  # Notify players of start
  message-players "Starting backup..." "$ARCHIVE_PATH"

  # Disable world autosaving
  execute-command "save-off"

  # Backup world
  START_TIME=$(date +"%s")

  if [[ "$BACKUP_DIRECTORY" != "" ]]; then
    # Ensure backup directory exists
    mkdir -p "$(dirname "$ARCHIVE_PATH")"

    case $COMPRESSION_ALGORITHM in
      # No compression
      "") tar -cf "$ARCHIVE_PATH" "${SERVER_WORLDS[@]}"
        ;;
      # With compression
      *) tar -cf - "${SERVER_WORLDS[@]}" | $COMPRESSION_ALGORITHM -cv -"$COMPRESSION_LEVEL" - > "$ARCHIVE_PATH" 2>> /dev/null
        ;;
    esac
    EXIT_CODES=("${PIPESTATUS[@]}")

    # tar exit codes: http://www.gnu.org/software/tar/manual/html_section/Synopsis.html
    # 0 = successful, 1 = some files differ, 2 = fatal
    if [ "${EXIT_CODES[0]}" == "1" ]; then
      log-warning "Some files may differ in the backup archive (file changed as read)"
      TAR_EXIT_CODE="0"
    else
      TAR_EXIT_CODE="${EXIT_CODES[0]}"
    fi

    ARCHIVE_EXIT_CODE="$(exit-code "$TAR_EXIT_CODE" "${EXIT_CODES[1]}")"
    if [ "$ARCHIVE_EXIT_CODE" -ne 0 ]; then
      log-fatal "Archive command exited with nonzero exit code $ARCHIVE_EXIT_CODE"
    fi
  fi

  if [[ "$RESTIC_REPO" != "" ]]; then
    RESTIC_TIMESTAMP="${TIMESTAMP:0:10} ${TIMESTAMP:11:2}:${TIMESTAMP:14:2}:${TIMESTAMP:17:2}"
    if [[ "$RESTIC_HOSTNAME" == "" ]]; then
      RESTIC_HOSTNAME_OPTION=()
    else
      RESTIC_HOSTNAME_OPTION=("--host" "$RESTIC_HOSTNAME")
    fi
    restic backup -r "$RESTIC_REPO" "${SERVER_WORLDS[@]}" --time "$RESTIC_TIMESTAMP" "$QUIET" "${RESTIC_HOSTNAME_OPTION[@]}"
    ARCHIVE_EXIT_CODE=$?
    if [ "$ARCHIVE_EXIT_CODE" -eq 3 ]; then
      log-warning "Incomplete snapshot taken (some files could not be read)"
      ARCHIVE_EXIT_CODE="0"
    else 
      if [ "$ARCHIVE_EXIT_CODE" -ne 0 ]; then
        # According to the restic docs, exit code is either 0, 1, or 3
        # Exit code 1 means fatal
        # See: https://restic.readthedocs.io/en/latest/040_backup.html
        log-fatal "No restic snapshot created (exit code $ARCHIVE_EXIT_CODE)"
      fi
    fi
  fi

  sync
  END_TIME=$(date +"%s")

  clean-up
}

if [[ "$LOCK_FILE" != "" ]]; then
  TIMEOUT_OPTION=()
  if [[ "$LOCK_FILE_TIMEOUT" != "" ]]; then
    TIMEOUT_OPTION=("-w" "$LOCK_FILE_TIMEOUT")
  fi
  (if ! flock "${TIMEOUT_OPTION[@]}" --no-fork 200; then
      log-fatal "Could not acquire lock on lock file: $LOCK_FILE"
      exit 1
    fi
  do-backup) 200>"$LOCK_FILE"
else
  do-backup
fi
