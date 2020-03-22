# Minecraft Backup
Backup script for Linux servers running a Minecraft server in a GNU Screen.

## Quick Start
```bash
# Download the scripts
git clone https://github.com/nicolaschan/minecraft-backup.git
./minecraft-backup/backup.sh -c -s $SCREEN_NAME -i $WORLD_DIR -o $BACKUP_DIR
```

## Why?
### Why not just put `tar` in crontab?
If the Minecraft server is currently running, you need to disable world autosaving, or you will likely get an error like this:
```
tar: /some/path/here/world/region/r.1.11.mca: file changed as we read it
```
This script will take care of disabling and then re-enabling autosaving for you, and also alert players in the chat of successful backups or errors.
This way, you don't have to shut down the server to take backups.
You'll also probably need some way to delete old backups, and this script can handle keeping either a number of most recent backups, or thinning them out based on hour/day/week. It can also use another backend such as [restic](https://github.com/restic/restic).

### Alternatives
This script is developed with vanilla servers in mind. If you are running a server with plugins or mods, then you can probably find a backup plugin/mod to do a similar job.

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for monthly backups
  - "sequential" - delete oldest backup
- Choose your own compression algorithm (tested with: `gzip`, `xz`, `zstd`)
- Print backup status and info to the Minecraft chat
- Customizable backup backends and Minecraft server interface (currently supports locally managed tar archives or [restic](https://github.com/restic/restic))

## Requirements
- Linux computer (tested on Arch Linux)
- GNU Screen (running your Minecraft server)
- Minecraft server

## Installation
```bash
# Download the scripts
git clone https://github.com/nicolaschan/minecraft-backup.git
```
**NOTE**: You will need to keep `backup.sh` in the same directory as the `src/` directory, since it looks for dependencies in `src/`.

## Usage Options
Command line options:
```text
-a    Compression algorithm (default: gzip)
-c    Enable chat messages
-d    Delete method: thin (default), sequential, none
-e    Compression file extension, exclude leading "." (default: gz)
-f    Output file name (default is the timestamp)
-g    Do not backup (exit) if screen is not running (default: always backup)
-h    Shows this help text
-i    Input directory (path to world folder)
-l    Compression level (default: 3)
-m    Maximum backups to keep, use -1 for unlimited (default: 128)
-o    Output directory
-p    Prefix that shows in Minecraft chat (default: Backup)
-q    Suppress warnings
-s    Minecraft server screen name
-v    Verbose mode
```

## Example Usage
### One-off Example
```bash
./backup.sh -c -s minecraft -i minecraft-server/world -o backups/
```
In this example, we print the status to the Minecraft chat (`-c`), use `minecraft` as the name of the screen, and save a backup of `minecraft-server/world` into `backups/` using the default thinning delete policy for old backups. While this works for performing a single backup, it is _highly_ recommended that you automate your backups.

### Automated with cron
- Edit the crontab:
```bash
crontab -e
```
- Example for hourly backups:
```
00 * * * * /path/to/minecraft-backup/backup.sh -c -s minecraft -i /path/to/minecraft-server/world -o /path/to/backups
```

### Automated using systemd timers
#### Simple example (single server)
`~/.config/systemd/user/minecraft-backup.timer`
```systemd
[Unit]
Description=Run Minecraft backup hourly

[Timer]
OnCalendar=hourly
Persistent=false
Unit=minecraft-backup.service

[Install]
WantedBy=timers.target
```
`~/.config/systemd/user/minecraft-backup.service`
```systemd
[Unit]
Description=Perform Minecraft backup

[Service]
Type=oneshot
ExecStart=/path/to/minecraft-backup/backup.sh -c -s minecraft -i /path/to/world -o /path/to/backups

[Install]
WantedBy=multi-user.target
```

Then you can run the following to enable the timer:
```bash
# enable the timer right now only
systemd --user start minecraft-backup.timer

# start the timer on reboot
systemd --user enable minecraft-backup.timer

# see status of timers
systemd --user list-timers
```

#### Advanced example (with restic and multiple servers)
If you have multiple servers, you can use `@` to create timers on-demand for each server. This assumes the server directories are named the same as the screen name.

`~/.config/systemd/user/minecraft-backup.timer`
```systemd
[Unit]
Description=Run Minecraft backup hourly

[Timer]
OnCalendar=hourly
Persistent=false
Unit=minecraft-backup@.service

[Install]
WantedBy=timers.target
```
`~/.config/systemd/user/minecraft-backup@.service`
```systemd
[Unit]
Description=Perform Minecraft backup

[Service]
Type=oneshot
Environment="RESTIC_PASSWORD_FILE=/path/to/restic-password.txt"
ExecStart=/path/to/minecraft-backup/backup-restic.sh -c -s %i -i /path/to/server/%i/world -o /path/to/restic-repo

[Install]
WantedBy=multi-user.target
```

To enable:
```bash
systemd --user enable minecraft-backup@your_server_name_here
```


## Retrieving Backups
Always test your backups! Backups are in the `tar` format and compressed depending on the option you choose. To restore, first decompress if necessary and then extract using `tar`. You may be able to do this in one command if `tar` supports your compression option, as is the case with `gzip`:

Example:
```bash
mkdir restored-world
# if using gzip:
gzip -cd 2017-07-31_00-00-00.tar.gz | tar xf - -C restored-world
# if using zstd:
zstd -cd 2017-07-31_00-00-00.tar.zst | tar xf - -C restored-world
```

Then you can move your restored world (`restored-world` in this case) to your Minecraft server folder and rename it (usually called `world`) so the Minecraft server uses it.

## Using [restic](https://github.com/restic/restic)
The `backup-restic.sh` script provides a similar interface for restic.
To specify your repository's password, you'll need to export the `$RESTIC_PASSWORD_FILE` or `$RESTIC_PASSWORD_COMMAND` environment variable.

```bash
restic init -r /path/to/restic-backups
touch restic-password.txt # make a new file for your restic password
chmod 600 restic-password.txt # make sure only you can read your password
echo "my_restic-password" > restic_password.txt
export RESTIC_PASSWORD_FILE=$(pwd)/restic_password.txt

/path/to/minecraft-backup/backup-restic.sh -c -s minecraft -i /path/to/minecraft-server/world -o /path/to/restic-backups
```

See above for an example automating this using systemd timers.

## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not always installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to the Minecraft server's GNU Screen
- It's surprising how much space backups can take--make sure you have enough empty space
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"

## Disclaimer
Backups are essential to the integrity of your Minecraft world. You should automate regular backups and **check that your backups work**. It is up to you to make sure that your backups work and that you have a reliable backup policy. 

Some backup tips:
- Drives get corrupted or fail! Backup to a _different_ drive than the one your server is running on, so if that drive fails then you have backups.
- _Automate_ backups so you never lose too much progress.
- Check that your backups work from time to time.

Please refer to the LICENSE (MIT License) for the full legal disclaimer.
