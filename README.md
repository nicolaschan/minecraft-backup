# Minecraft Backup
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/nicolaschan/minecraft-backup/CI)
[![codecov](https://codecov.io/gh/nicolaschan/minecraft-backup/branch/master/graph/badge.svg?token=LCbVC4TbYJ)](https://codecov.io/gh/nicolaschan/minecraft-backup)

Backup script for Linux servers running a Minecraft server. 
Supports servers running in [GNU screen](https://en.wikipedia.org/wiki/GNU_Screen), [tmux](https://en.wikipedia.org/wiki/Tmux), or with [rcon](https://wiki.vg/RCON) enabled.

### Disclaimer
Backups are essential to the integrity of your Minecraft world. You should automate regular backups and **check that your backups work**. While this script has been used in production for several years, it is up to you to make sure that your backups work and that you have a reliable backup policy. 

Please refer to the LICENSE (MIT License) for the full legal disclaimer.

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for monthly backups
  - "sequential" - delete oldest backup
- Choose your own compression algorithm (tested with: `gzip`, `xz`, `zstd`)
- Works on vanilla -- no plugins required
- Able to print backup status and info to the Minecraft chat

## Why not just use `tar` directly?
If the Minecraft server is currently running, you need to disable world autosaving, or you will likely get an error like this:
```
tar: /some/path/here/world/region/r.1.11.mca: file changed as we read it
```
This script will take care of disabling and then re-enabling autosaving for you, and also alert players in the chat of successful backups or errors. This script also manages deleting old backups.

## Requirements
- Linux computer (tested on Ubuntu)
- GNU Screen (running your Minecraft server)
- Minecraft server 

## Quick Start
```bash
wget https://raw.githubusercontent.com/nicolaschan/minecraft-backup/master/backup.sh
chmod +x backup.sh
```

Command line options:
```text
-a    Compression algorithm (default: gzip)
-c    Enable chat messages
-d    Delete method: thin (default), sequential, none
-e    Compression file extension, exclude leading "." (default: gz)
-f    Output file name (default is the timestamp)
-h    Shows this help text
-i    Input directory (path to world folder)
-l    Compression level (default: 3)
-m    Maximum backups to keep, use -1 for unlimited (default: 128)
-o    Output directory
-p    Prefix that shows in Minecraft chat (default: Backup)
-q    Suppress warnings
-s    Minecraft server screen name
-v    Verbose mode
-w    Window manager: screen (default) or tmux
```

Example usage of command line options:
```bash
./backup.sh -c -i /home/nicolas/mcserver/world -o /mnt/storage/backups -s minecraft
```
This will show chat messages (`-c`) in the screen called "minecraft" and save a backup of `/home/nicolas/mcserver/world` into `/mnt/storage/backups` using the default thinning deletion policy for old backups.

### Create a cron job to automatically backup:
- Edit the crontab with `crontab -e`
- Example for hourly backups: `00 * * * * /path/to/backup.sh ...`
  
## Retrieving Backups
Always test your backups! Backups are in the `tar` format and compressed depending on the option you choose. To restore, first decompress if necessary and then extract using tar. You may be able to do this in one command if `tar` supports your compression option, as is the case with `gzip`:

Example:
```bash
mkdir restored-world
cd restored-world
tar -xzvf /path/to/backups/2019-04-09_02-15-01.tar.gz
```

Then you can move your restored world (`restored-world` in this case) to your Minecraft server folder and rename it (usually called `world`) so the Minecraft server uses it.

## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to the Minecraft server's GNU Screen
- It's surprising how much space backups can take--make sure you have enough empty space
- Do not put trailing `/` in the `SERVER_DIRECTORY` or `BACKUP_DIRECTORY`
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"
