# Minecraft Backup
Backup script for Linux servers running Minecraft in a GNU Screen

### Still in development, so use at your own risk!

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for monthly backups
  - "sequential" - delete oldest backup
- Choose your own compression algorithm (tested with: `gzip`, `xz`, `zstd`)
- Able to print backup status and info to the Minecraft chat

## Requirements
- Linux computer (tested on Ubuntu)
- GNU Screen (running your Minecraft server)
- Minecraft server (tested with Vanilla 1.10.2 only)

## Installation
1. Download the script: `$ wget https://raw.githubusercontent.com/nicolaschan/minecraft-backup/master/backup.sh`
2. Configure the variables (in the top of the script)

  ```bash
SCREEN_NAME="PrivateSurvival" # Name of the GNU Screen your Minecraft server is running in
SERVER_DIRECTORY="/home/server/MinecraftServers/PrivateSurvival" # Server directory, NOT the world; world is SERVER_DIRECTORY/world
BACKUP_DIRECTORY="/media/server/ExternalStorage/Backups/PrivateSurvivalBackups" # Directory to save backups in
NUMBER_OF_BACKUPS_TO_KEEP=128 # -1 indicates unlimited
DELETE_METHOD="thin" # Choices: thin, sequential, none; sequential: delete oldest; thin: keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
COMPRESSION_ALGORITHM="zstd" # Leave empty for no compression
COMPRESSION_FILE_EXTENSION=".zst" # Leave empty for no compression; Precede with a . (for example: ".gz")
COMPRESSION_LEVEL=3 # Passed to the compression algorithm
ENABLE_CHAT_MESSAGES=true # Tell players in Minecraft chat about backup status
PREFIX="Backup" # Shows in the chat message
DEBUG=true # Enable debug messages
  ```
3. Create a cron job to automatically backup

  a. Edit the crontab: `$ crontab -e`
  
  b. Example for hourly backups: `00 * * * * /path/to/backup.sh`
  
## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to the Minecraft server's GNU Screen
- It's surprising how much space backups can take--make sure you have enough empty space
- `SERVER_DIRECTORY` should be the server directory, not the `world` directory
- Do not put trailing `/` in the `SERVER_DIRECTORY` or `BACKUP_DIRECTORY`
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"
