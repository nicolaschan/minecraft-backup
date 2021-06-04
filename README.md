# Minecraft Backup
[![CI](https://github.com/nicolaschan/minecraft-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/nicolaschan/minecraft-backup/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/nicolaschan/minecraft-backup/branch/master/graph/badge.svg?token=LCbVC4TbYJ)](https://codecov.io/gh/nicolaschan/minecraft-backup)

Backup script for Minecraft servers on Linux. 
Supports servers running in [screen](https://en.wikipedia.org/wiki/GNU_Screen), [tmux](https://en.wikipedia.org/wiki/Tmux), or with [RCON](https://wiki.vg/RCON) enabled. Supports `tar` file or [`restic`](https://restic.net/) backup backends.

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for weekly backups
  - "sequential" - delete oldest backup
- Works on vanilla (no plugins required)
- Print backup status to the Minecraft chat

## Install
```bash
wget https://github.com/nicolaschan/minecraft-backup/releases/latest/download/backup.sh
chmod +x backup.sh
```

Make sure your system has `tar` and your chosen compression algorithm (`gzip` by default) installed.
If using RCON, you will also need to have the [`xxd`](https://linux.die.net/man/1/xxd) command.

## Usage
```bash
# If connecting with RCON:
./backup.sh -c -i /home/user/server/world -o /mnt/storage/backups -s localhost:25575:secret -w rcon

# If running on screen called "minecraft":
./backup.sh -c -i /home/user/server/world -o /mnt/storage/backups -s minecraft

# If running on tmux session 0:
./backup.sh -c -i /home/user/server/world -o /mnt/storage/backups -s 0 -w tmux 

# Using restic (and RCON)
export RESTIC_PASSWORD="restic-pass-secret" # your password here
./backup.sh -c -i /home/user/server/world -r /mnt/storage/backups-restic -s localhost:25575:secret -w rcon

# Using Docker and RCON
# You will have to set up networking so that this Docker image can access the RCON server
# In this example, the RCON server hostname is `server-host`
docker run \ 
  -v /home/user/server/world:/mnt/server \
  -v /mnt/storage/backups:/mnt/backups \
  ghcr.io/nicolaschan/minecraft-backup -c -i /mnt/server -o /mnt/backups -s server-host:25575:secret -w rcon
```

This will show chat messages (`-c`) and save a backup of `/home/user/server/world` into `/mnt/storage/backups` using the default thinning deletion policy for old backups.

Command line options:
```text
-a    Compression algorithm (default: gzip)
-c    Enable chat messages
-d    Delete method: thin (default), sequential, none
-e    Compression file extension, exclude leading "." (default: gz)
-f    Output file name (default is the timestamp)
-h    Shows this help text
-i    Input directory (path to world folder, use -i once for each world)
-l    Compression level (default: 3)
-m    Maximum backups to keep, use -1 for unlimited (default: 128)
-o    Output directory
-p    Prefix that shows in Minecraft chat (default: Backup)
-q    Suppress warnings
-r    Restic repo name (if using restic)
-s    Screen name, tmux session name, or hostname:port:password for RCON
-t    Enable lock file (lock file not used by default)
-u    Lock file timeout seconds (empty = unlimited)
-v    Verbose mode
-w    Window manager: screen (default), tmux, RCON
```

### Automate backups with cron
- Edit the crontab with `crontab -e`
- Example for hourly backups:
```
00 * * * * /path/to/backup.sh -c -i /home/user/server/world -o /mnt/storage/backups -s minecraft
```

## Retrieving Backups
Always test your backups! Backups are in the `tar` format and compressed depending on the option you choose. To restore, first decompress if necessary and then extract using tar. You may be able to do this in one command if `tar` supports your compression option, as is the case with `gzip`:

Example:
```bash
mkdir restored-world
cd restored-world
tar -xzvf /path/to/backups/2019-04-09_02-15-01.tar.gz
```

The restored worlds should be inside the `restored-world` directory, possibly nested under the parent directories. Then you can move your restored world to your Minecraft server folder under the proper name and path so the Minecraft server uses it.

### With `restic`
Use [`restic restore`](https://restic.readthedocs.io/en/latest/050_restore.html) to restore from backup.

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

## Known Issues
There is a Minecraft bug [MC-217729](https://bugs.mojang.com/projects/MC/issues/MC-217729) in recent Minecraft server versions that cause them to automatically save the world even after receiving the `save-off` command. Until this is fixed, there is a chance that the backup will fail because the world files are modified by Minecraft in the process of creating the backup. This script will try to detect and report this problem if it does occur.

## Disclaimer
Backups are essential to the integrity of your Minecraft world. You should automate regular backups and **check that your backups work**. It is up to you to make sure that your backups work and that you have a reliable backup policy. 

Some backup tips:
- Drives get corrupted or fail! Backup to a _different_ drive than the one your server is running on, so if your main drive fails then you have backups.
- _Automate_ backups so you never lose too much progress.
- Check that your backups work from time to time.

Please refer to the LICENSE (MIT License) for the full legal disclaimer.
