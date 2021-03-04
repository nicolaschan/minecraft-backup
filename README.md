# Minecraft Backup
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/nicolaschan/minecraft-backup/CI)
[![codecov](https://codecov.io/gh/nicolaschan/minecraft-backup/branch/master/graph/badge.svg?token=LCbVC4TbYJ)](https://codecov.io/gh/nicolaschan/minecraft-backup)

Backup script for Minecraft servers on Linux. 
Supports servers running in [screen](https://en.wikipedia.org/wiki/GNU_Screen), [tmux](https://en.wikipedia.org/wiki/Tmux), or with [RCON](https://wiki.vg/RCON) enabled.

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for weekly backups
  - "sequential" - delete oldest backup
- Works on vanilla (no plugins required)
- Print backup status to the Minecraft chat

## Install
```bash
wget https://raw.githubusercontent.com/nicolaschan/minecraft-backup/master/backup.sh
chmod +x backup.sh
```

## Usage
```bash
./backup.sh -c -i /home/user/mcserver/world -o /mnt/storage/backups -s minecraft
```

This will show chat messages (`-c`) in the screen called "minecraft" and save a backup of `/home/user/mcserver/world` into `/mnt/storage/backups` using the default thinning deletion policy for old backups.

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
-s    Screen name, tmux session name, or hostname:port:password for RCON
-v    Verbose mode
-w    Window manager: screen (default), tmux, RCON 
```

### Automate backups with cron
- Edit the crontab with `crontab -e`
- Example for hourly backups:
```
00 * * * * /path/to/backup.sh -c -i /home/user/mcserver/world -o /mnt/storage/backups -s minecraft
```

## Retrieving Backups
Always test your backups! Backups are in the `tar` format and compressed depending on the option you choose. To restore, first decompress if necessary and then extract using tar. You may be able to do this in one command if `tar` supports your compression option, as is the case with `gzip`:

Example:
```bash
mkdir restored-world
cd restored-world
tar -xzvf /path/to/backups/2019-04-09_02-15-01.tar.gz
```

Then you can move your restored world (`restored-world` in this case) to your Minecraft server folder and rename it (usually called `world`) so the Minecraft server uses it.

## Why not use `tar` directly?
If you use `tar` while the server is running, you will likely get an error like this because Minecraft autosaves the world periodically:
```
tar: /some/path/here/world/region/r.1.11.mca: file changed as we read it
```
To fix this problem, the backup script disables autosaving with the `save-off` Minecraft command before running `tar` and then re-enables autosaving after `tar` is done. 

## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to the Minecraft server's GNU Screen
- It's surprising how much space backups can take--make sure you have enough empty space
- Do not put trailing `/` in the `SERVER_DIRECTORY` or `BACKUP_DIRECTORY`
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"

## Disclaimer
Backups are essential to the integrity of your Minecraft world. You should automate regular backups and **check that your backups work**. It is up to you to make sure that your backups work and that you have a reliable backup policy. 

Some backup tips:
- Drives get corrupted or fail! Backup to a _different_ drive than the one your server is running on, so if your main drive fails then you have backups.
- _Automate_ backups so you never lose too much progress.
- Check that your backups work from time to time.

Please refer to the LICENSE (MIT License) for the full legal disclaimer.
