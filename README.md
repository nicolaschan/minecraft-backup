# Minecraft Backup
Backup script for Linux servers running a Minecraft server in a GNU Screen

### Still in development, so use at your own risk!

## Features
- Create backups of your world folders
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for monthly backups
  - "sequential" - delete oldest backup
- Choose your own compression algorithm (tested with: `gzip`, `xz`, `zstd`)
- Able to print backup status and info to the Minecraft chat
- Can back up as many worlds as you like

## Requirements
- Linux computer (tested on Ubuntu)
- GNU Screen (running your Minecraft server)
- Minecraft server (tested with Vanilla 1.10.2 only)

## Installation
1. Download the script: `$ wget https://raw.githubusercontent.com/nicolaschan/minecraft-backup/master/backup.sh`
2. Mark as executable: `$ chmod +x backup.sh`
3. Configure the variables (in the top of the script)
   or use the commandline options (see ./backup.sh -h for help)

  ```bash
SCREEN_NAME="PrivateSurvival" # Name of the GNU Screen your Minecraft server is running in
SERVER_WORLDS=() # Array for input paths (paths of the worlds to back up)
SERVER_WORLDS[0]="/home/server/MinecraftServers/PrivateSurvival/world" # World you want to back up
BACKUP_DIRECTORYS=() # Array for directory to save backups in (invoke in same order as input directorys with -i)
BACKUP_DIRECTORY[0]="/media/server/ExternalStorage/Backups/PrivateSurvivalBackups" # Directory to save backups in
NUMBER_OF_BACKUPS_TO_KEEP=128 # -1 indicates unlimited
DELETE_METHOD="thin" # Choices: thin, sequential, none; sequential: delete oldest; thin: keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
COMPRESSION_ALGORITHM="zstd" # Leave empty for no compression
COMPRESSION_FILE_EXTENSION=".zst" # Leave empty for no compression; Precede with a . (for example: ".gz")
COMPRESSION_LEVEL=3 # Passed to the compression algorithm
ENABLE_CHAT_MESSAGES=true # Tell players in Minecraft chat about backup status
ENABLE_JOINED_BACKUP_MESSAGE=false # Print a combined Backup info messsage after all Backups are finished - if multiple Backups were performed
PREFIX="Backup" # Shows in the chat message
DEBUG=true # Enable debug messages
  ```
4. Create a cron job to automatically backup

  a. Edit the crontab: `$ crontab -e`
  
  b. Example for hourly backups: `00 * * * * /path/to/backup.sh`
  
## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to the Minecraft server's GNU Screen
- It's surprising how much space backups can take--make sure you have enough empty space
- Do not put trailing `/` in the `SERVER_WORLDS` or `BACKUP_DIRECTORYs`
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"
- you can back up multiple worlds into seperate folders or all into one
- the backup for first specified world folder goes into the first specified backup folder and so on...
