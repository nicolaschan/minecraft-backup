#!/usr/bin/env bash

# Minecraft server automatic backup management script
# by Nicolas Chan
# https://github.com/nicolaschan/minecraft-backup
# MIT License
#
# For Minecraft servers running in a GNU screen.
# For most convenience, run automatically with cron.

# Default Configuration 
SCREEN_NAME="" # Name of the GNU Screen your Minecraft server is running in
SERVER_WORLD="" # Server world directory
BACKUP_DIRECTORY="" # Directory to save backups in
EXIT_IF_NO_SCREEN=false # Skip backup if there is no minecraft screen running
ENABLE_CHAT_MESSAGES=false # Tell players in Minecraft chat about backup status
PREFIX="Backup" # Shows in the chat message
DEBUG=false # Enable debug messages
SUPPRESS_WARNINGS=false # Suppress warnings

OPTIND=1
while getopts 'cghi:o:p:qs:v' FLAG; do
  case $FLAG in
    a) COMPRESSION_ALGORITHM=$OPTARG ;;
    c) ENABLE_CHAT_MESSAGES=true ;;
    d) DELETE_METHOD=$OPTARG ;;
    e) COMPRESSION_FILE_EXTENSION=".$OPTARG" ;;
    f) TIMESTAMP=$OPTARG ;;
    g) EXIT_IF_NO_SCREEN=true ;;
    h) echo "Minecraft Backup Script: https://github.com/nicolaschan/minecraft-backup.git"
       echo "-c    Enable chat messages"
       echo "-g    Do not backup (exit) if screen is not running (default: always backup)"
       echo "-h    Shows this help text"
       echo "-i    Input directory (path to world folder)"
       echo "-o    Output directory"
       echo "-p    Prefix that shows in Minecraft chat (default: Backup)"
       echo "-q    Suppress warnings"
       echo "-s    Minecraft server screen name"
       echo "-v    Verbose mode"
       exit 0
       ;;
    i) SERVER_WORLD=$OPTARG ;;
    l) COMPRESSION_LEVEL=$OPTARG ;;
    m) MAX_BACKUPS=$OPTARG ;;
    o) BACKUP_DIRECTORY=$OPTARG ;;
    p) PREFIX=$OPTARG ;;
    q) SUPPRESS_WARNINGS=true ;;
    s) SCREEN_NAME=$OPTARG ;;
    v) DEBUG=true ;;
    *) ;;
  esac
done

BASE_DIR=$(dirname "$(realpath "$0")")

if ! [[ -d "$BASE_DIR/src" ]]; then
  echo -e "The src/ directory needs to be in the same directory as backup.sh because it contains other scripts that backup.sh depends on.\n\
	   You should download the entire repository:
   	   git clone https://github.com/nicolaschan.com/minecraft-backup.git
	  "
  exit 1
fi

# shellcheck source=src/logging.sh
source "$BASE_DIR/src/logging.sh" \
  -q "$SUPPRESS_WARNINGS" \
  -v "$DEBUG"

# Check for missing encouraged arguments
if [[ $SCREEN_NAME == "" ]]; then
  log-warning "Minecraft screen name not specified (use -s)"
fi

# Check for required arguments
MISSING_CONFIGURATION=false
if [[ $SERVER_WORLD == "" ]]; then
  log-fatal "Server world not specified (use -i)"
  MISSING_CONFIGURATION=true
fi
if [[ $BACKUP_DIRECTORY == "" ]]; then
  log-fatal "Backup directory not specified (use -o)"
  MISSING_CONFIGURATION=true
fi
if $MISSING_CONFIGURATION; then
  exit 1
fi

"$BASE_DIR/src/core.sh" \
  "$BASE_DIR/src/exec-methods/screen.sh" \
    -s "$SCREEN_NAME" \
  -- \
  "$BASE_DIR/src/backup-methods/restic.sh" \
    -i "$SERVER_WORLD" \
    -o "$BACKUP_DIRECTORY" \
  -- \
    -c "$ENABLE_CHAT_MESSAGES" \
    -g "$EXIT_IF_NO_SCREEN" \
    -p "$PREFIX" \
    -q "$SUPPRESS_WARNINGS" \
    -v "$DEBUG"
