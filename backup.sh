#!/bin/bash

# Minecraft server automatic backup management script
# by Nicolas Chan
# MIT License
#
# For Minecraft servers running in a GNU screen.
# For most convenience, run automatically with cron.

# Configuration
SCREEN_NAME="PrivateSurvival" # Name of the GNU Screen your Minecraft server is running in
SERVER_DIRECTORY="/home/server/MinecraftServers/PrivateSurvival" # Server directory, NOT the world; world is SERVER_DIRECTORY/world
BACKUP_DIRECTORY="/media/server/ExternalStorage/Backups/PrivateSurvivalBackups" # Directory to save backups in
NUMBER_OF_BACKUPS_TO_KEEP=512 # -1 indicates unlimited
DELETE_METHOD="thin" # Choices: thin, sequential, none; sequential: delete oldest; thin: keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
COMPRESSION_ALGORITHM="zstd" # Leave empty for no compression
COMPRESSION_FILE_EXTENSION=".zst" # Leave empty for no compression; Precede with a . (for example: ".gz")
COMPRESSION_LEVEL=3 # Passed to the compression algorithm
ENABLE_CHAT_MESSAGES=true # Tell players in Minecraft chat about backup status
PREFIX="Backup" # Shows in the chat message
DEBUG=true # Enable debug messages

# Other Variables (do not modify)
DATE_FORMAT="%F_%H-%M-%S"
TIMESTAMP=$(date +$DATE_FORMAT)
ARCHIVE_FILE_NAME=$TIMESTAMP.tar$COMPRESSION_FILE_EXTENSION
ARCHIVE_PATH=$BACKUP_DIRECTORY/$ARCHIVE_FILE_NAME

# Minecraft server screen interface functions
message-players () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "gray"
}
execute-command () {
  local COMMAND=$1
  screen -S $SCREEN_NAME -p 0 -X stuff "$COMMAND$(printf \\r)"
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
  echo "$MESSAGE ($HOVER_MESSAGE)"
  if $ENABLE_CHAT_MESSAGES; then
    sleep 0.5
    screen -S $SCREEN_NAME -p 0 -X stuff "tellraw @a [\"\",{\"text\":\"[$PREFIX] \",\"color\":\"gray\",\"italic\":true},{\"text\":\"$MESSAGE\",\"color\":\"$COLOR\",\"italic\":true,\"hoverEvent\":{\"action\":\"show_text\",\"value\":{\"text\":\"\",\"extra\":[{\"text\":\"$HOVER_MESSAGE\"}]}}}]$(printf \\r)"
  fi
}

# Notify players of start
message-players "Starting backup..." "$ARCHIVE_FILE_NAME"

# Sequential delete method
delete-sequentially () {
  local BACKUPS=($(ls $BACKUP_DIRECTORY))
  while [[ $NUMBER_OF_BACKUPS_TO_KEEP -ge 0 && ${#BACKUPS[@]} -ge $NUMBER_OF_BACKUPS_TO_KEEP ]]; do
    rm $BACKUP_DIRECTORY/${BACKUPS[0]}
    message-players "Deleted old backup" "${BACKUPS[0]}"
    BACKUPS=($(ls $BACKUP_DIRECTORY))
  done
}

# Thinning delete method
delete-thinning () {
  local HOURLY_BLOCK_SIZE=96
  local DAILY_BLOCK_SIZE=30
  local BACKUPS=($(ls -r $BACKUP_DIRECTORY)) # List newest first

  local OLDEST_HOURLY_BACKUP=${BACKUPS[HOURLY_BLOCK_SIZE - 1]}
  local OLDEST_HOURLY_BACKUP_HOUR=${OLDEST_HOURLY_BACKUP:11:5}

  # DEBUG: Log the oldest hourly backup to console
  if $DEBUG; then
    echo "Oldest hourly backup is: $OLDEST_HOURLY_BACKUP"
  fi

  # If the oldest hourly backup was not at midnight, delete it
  if [ "$OLDEST_HOURLY_BACKUP_HOUR" != "00-00" ] && [[ "$OLDEST_HOURLY_BACKUP" != "" ]]; then
    rm $BACKUP_DIRECTORY/$OLDEST_HOURLY_BACKUP
    message-players "Deleted old backup" "$OLDEST_HOURLY_BACKUP"
  else
    # Oldest hourly backup was at midnight, so it is now a daily backup
    local OLDEST_DAILY_BACKUP=${BACKUPS[HOURLY_BLOCK_SIZE + DAILY_BLOCK_SIZE - 1]}
    local OLDEST_DAILY_BACKUP_DAY=${OLDEST_DAILY_BACKUP:8:2}

    # DEBUG: Log the oldest hourly backup to console
    if $DEBUG; then
      echo "Oldest daily backup is: $OLDEST_DAILY_BACKUP"
    fi

    # If the oldest daily backup was not on the 1st, delete it
    if [ "$OLDEST_DAILY_BACKUP_DAY" -ne 1 ] && [[ "$OLDEST_DAILY_BACKUP" != "" ]]; then
      rm $BACKUP_DIRECTORY/$OLDEST_DAILY_BACKUP
      message-players "Deleted old backup" "$OLDEST_DAILY_BACKUP"
    else
      # Oldest daily backup was on the 1st, so it is now a monthly backup
      delete-sequentially # Delete old monthly backups
    fi
  fi
}

# Disable world autosaving
execute-command "save-off"

# Backup world
START_TIME=$(date +"%s")
case $COMPRESSION_ALGORITHM in
  "") # No compression
    tar -cf $ARCHIVE_PATH -C $SERVER_DIRECTORY world
    ;;
  *) # With compression
    tar -cf - -C $SERVER_DIRECTORY world | $COMPRESSION_ALGORITHM -cv -$COMPRESSION_LEVEL - > $ARCHIVE_PATH
    ;;
esac
sync $ARCHIVE_PATH
END_TIME=$(date +"%s")

# Enable world autosaving
execute-command "save-on"

# Save the world
execute-command "save-all"

# Delete old backups
delete-old-backups () {
  case $DELETE_METHOD in
    "sequential") delete-sequentially
      ;;
    "thin") delete-thinning
      ;;
  esac
}

# Notify players of completion
WORLD_SIZE_KB=$(du --max-depth=0 $SERVER_DIRECTORY/world | awk '{print $1}')
ARCHIVE_SIZE_KB=$(du $ARCHIVE_PATH | awk '{print $1}')
COMPRESSION_PERCENT=$(($ARCHIVE_SIZE_KB * 100 / $WORLD_SIZE_KB))
ARCHIVE_SIZE=$(du -h $ARCHIVE_PATH | awk '{print $1}')
BACKUP_DIRECTORY_SIZE=$(du -h --max-depth=0 $BACKUP_DIRECTORY | awk '{print $1}')
TIME_DELTA=$((END_TIME - START_TIME))

if [[ "$ARCHIVE_SIZE" != "" ]]; then
  message-players-success "Backup complete!" "$TIME_DELTA s, $ARCHIVE_SIZE/$BACKUP_DIRECTORY_SIZE, $COMPRESSION_PERCENT%"
  delete-old-backups
else
  message-players-error "Backup was not saved!" "Please notify an administrator"
fi
