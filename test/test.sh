#!/usr/bin/env bash

# Helper functions

TEST_DIR="test"
TEST_TMP="$TEST_DIR/tmp"
SCREEN_TMP="tmp-screen"
RCON_PORT="8088"
RCON_PASSWORD="supersecret"
export RESTIC_PASSWORD="restic-pass-secret"
setUp () {
  chmod -R 755 "$TEST_TMP" || true
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP/server/world"
  mkdir -p "$TEST_TMP/backups"
  echo "file1" > "$TEST_TMP/server/world/file1.txt"
  echo "file2" > "$TEST_TMP/server/world/file2.txt"
  echo "file3" > "$TEST_TMP/server/world/file3.txt"
  restic init -r "$TEST_TMP/backups-restic" -q

  screen -dmS "$SCREEN_TMP" bash
  while ! screen -S "$SCREEN_TMP" -Q "select" . &>/dev/null; do
    sleep 0.1
  done
  screen -S "$SCREEN_TMP" -X stuff "cat > $TEST_TMP/screen-output\n"
  tmux new-session -d -s "$SCREEN_TMP"
  while ! tmux has-session -t "$SCREEN_TMP" 2>/dev/null; do
    sleep 0.1
  done
  tmux send-keys -t "$SCREEN_TMP" "cat > $TEST_TMP/tmux-output" ENTER
  python test/mock_rcon.py "$RCON_PORT" "$RCON_PASSWORD" > "$TEST_TMP/rcon-output" &
  echo "$!" > "$TEST_TMP/rcon-pid"

  while ! [[ (-f "$TEST_TMP/screen-output")  && (-f "$TEST_TMP/tmux-output") && (-f "$TEST_TMP/rcon-output") ]]; do
    sleep 0.1
  done
}

tearDown () {
  RCON_PID="$(cat "$TEST_TMP/rcon-pid")"
  kill "$RCON_PID" >/dev/null 2>&1 || true
  screen -S "$SCREEN_TMP" -X quit >/dev/null 2>&1 || true
  tmux kill-session -t "$SCREEN_TMP" >/dev/null 2>&1 || true
  sleep 0.1
}

assert-equals-directory () {
  if ! [ -e "$1" ]; then
    fail "File not found: $1"
  fi
  if [ -d "$1" ]; then
    for FILE in "$1"/*; do
      assert-equals-directory "$FILE" "$2/${FILE##"$1"}"
    done
  else
    assertEquals "$(cat "$1")" "$(cat "$2")"
  fi
}

check-backup-full-paths () {
  BACKUP_ARCHIVE="$1"
  WORLD_DIR="$2"
  mkdir -p "$TEST_TMP/restored"
  tar --extract --file "$BACKUP_ARCHIVE" --directory "$TEST_TMP/restored"
  assert-equals-directory "$WORLD_DIR" "$TEST_TMP/restored/$WORLD_DIR"
  rm -rf "$TEST_TMP/restored"
}

check-backup () {
  BACKUP_ARCHIVE="$1"
  check-backup-full-paths "$TEST_TMP/backups/$BACKUP_ARCHIVE" "$TEST_TMP/server/world"
}

check-latest-backup-restic () {
  WORLD_DIR="$TEST_TMP/server/world"
  restic restore latest -r "$TEST_TMP/backups-restic" --target "$TEST_TMP/restored" -q
  assert-equals-directory "$WORLD_DIR" "$TEST_TMP/restored/$WORLD_DIR"
  rm -rf "$TEST_TMP/restored"
}

# Tests

test-restic-explicit-hostname () {
  EXPECTED_HOSTNAME="${HOSTNAME}blahblah"
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP" -H "$EXPECTED_HOSTNAME"
  check-latest-backup-restic
  LATEST_BACKUP_HOSTNAME=$(restic -r "$TEST_TMP/backups-restic" snapshots latest --json | jq -r '.[0]["hostname"]')
  assertEquals "$EXPECTED_HOSTNAME" "$LATEST_BACKUP_HOSTNAME"
}

test-restic-default-hostname () {
  EXPECTED_HOSTNAME="${HOSTNAME}"
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-latest-backup-restic
  LATEST_BACKUP_HOSTNAME=$(restic -r "$TEST_TMP/backups-restic" snapshots latest --json | jq -r '.[0]["hostname"]')
  assertEquals "$EXPECTED_HOSTNAME" "$LATEST_BACKUP_HOSTNAME"
}

test-backup-defaults () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.gz"
}

test-backup-multiple-worlds () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  cp -r "$TEST_TMP/server/world" "$TEST_TMP/server/world_nether"
  cp -r "$TEST_TMP/server/world" "$TEST_TMP/server/world_the_end"
  ./backup.sh -i "$TEST_TMP/server/world" -i "$TEST_TMP/server/world_nether" -i "$TEST_TMP/server/world_the_end" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  mkdir -p "$TEST_TMP/restored"
  tar --extract --file "$TEST_TMP/backups/$TIMESTAMP.tar.gz" --directory "$TEST_TMP/restored"
  assert-equals-directory "$TEST_TMP/server/world" "$TEST_TMP/restored/$TEST_TMP/server/world"
  assert-equals-directory "$TEST_TMP/server/world_nether" "$TEST_TMP/restored/$TEST_TMP/server/world_nether"
  assert-equals-directory "$TEST_TMP/server/world_the_end" "$TEST_TMP/restored/$TEST_TMP/server/world_the_end"
}

test-file-changed-as-read-warning () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  dd if=/dev/urandom of="$TEST_TMP/server/world/random" &
  DD_PID="$!"
  OUTPUT="$(./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  kill "$DD_PID"
  assertEquals 0 "$EXIT_CODE"
  assertContains "$OUTPUT" "Some files may differ in the backup archive"

  # Check that the backup actually resulted in a valid tar 
  assertTrue '[ -f '"$TEST_TMP/backups/$TIMESTAMP.tar.gz"' ]'

  mkdir -p "$TEST_TMP/restored"
  tar --extract --file "$TEST_TMP/backups/$TIMESTAMP.tar.gz" --directory "$TEST_TMP/restored"
  assert-equals-directory "$WORLD_DIR/file1.txt" "$TEST_TMP/restored/$WORLD_DIR/file1.txt"
  assert-equals-directory "$WORLD_DIR/file2.txt" "$TEST_TMP/restored/$WORLD_DIR/file2.txt"
  assert-equals-directory "$WORLD_DIR/file3.txt" "$TEST_TMP/restored/$WORLD_DIR/file3.txt"
}

test-lock-defaults () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -t "$TEST_TMP/lockfile" -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.gz"
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +1 hour")"
  ./backup.sh -t "$TEST_TMP/lockfile" -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.gz"
}

test-lock-timeout () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  flock "$TEST_TMP/lockfile" sleep 10 &
  OUTPUT=$(./backup.sh -t "$TEST_TMP/lockfile" -u 0 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP")
  assertNotEquals 0 "$?"
  assertContains "$OUTPUT" "Could not acquire lock on lock file: $TEST_TMP/lockfile"
}

test-restic-incomplete-snapshot () {
  chmod 000 "$TEST_TMP/server/world/file1.txt"
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP")"
  assertEquals 1 "$(restic list snapshots -r "$TEST_TMP/backups-restic" | wc -l)"
  assertContains "$OUTPUT" "Incomplete snapshot taken"
}

test-restic-no-snapshot () {
  rm -rf "$TEST_TMP/server"
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP")"
  EXIT_CODE="$?"
  assertNotEquals 0 "$EXIT_CODE"
  assertContains "$OUTPUT" "No restic snapshot created"
}

test-restic-thinning-too-few () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -m 10 -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  assertNotEquals 0 "$EXIT_CODE"
  assertContains "$OUTPUT" "Thinning delete with restic requires at least 70 snapshots to be kept."
}

test-restic-thinning-delete-long () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i day")"
    ./backup.sh -m -1 -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  EXPECTED_TIMESTAMPS=(
    # Weekly
    "2021-01-03 00:00:00"
    "2021-01-10 00:00:00"
    "2021-01-17 00:00:00"
    "2021-01-24 00:00:00"
    "2021-01-31 00:00:00"

    # Daily (30)
    "2021-03-13 00:00:00"
    "2021-03-14 00:00:00"
    "2021-03-15 00:00:00"
    "2021-03-16 00:00:00"
    "2021-03-17 00:00:00"
    "2021-03-18 00:00:00"

    # Hourly (24)
    "2021-03-19 00:00:00"
    "2021-03-20 00:00:00"
    "2021-03-21 00:00:00"
    "2021-03-22 00:00:00"
    "2021-03-23 00:00:00"
    "2021-03-24 00:00:00"
    "2021-03-25 00:00:00"
    "2021-03-26 00:00:00"

    # Sub-hourly (16)
    "2021-03-26 00:00:00"
    "2021-03-27 00:00:00"
    "2021-03-28 00:00:00"
    "2021-03-29 00:00:00"
    "2021-03-30 00:00:00"
    "2021-03-31 00:00:00"
    "2021-04-01 00:00:00"
    "2021-04-02 00:00:00"
    "2021-04-03 00:00:00"
    "2021-04-04 00:00:00"
    "2021-04-05 00:00:00"
    "2021-04-06 00:00:00"
    "2021-04-07 00:00:00"
    "2021-04-08 00:00:00"
    "2021-04-09 00:00:00"
    "2021-04-10 00:00:00"
  )
  SNAPSHOTS="$(restic snapshots -r "$TEST_TMP/backups-restic")"
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    assertContains "$SNAPSHOTS" "$TIMESTAMP" 
  done
}

test-restic-defaults () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-latest-backup-restic
}

test-backup-spaces-in-directory () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  WORLD_SPACES="$TEST_TMP/minecraft server/the world"
  mkdir -p "$(dirname "$WORLD_SPACES")"
  BACKUP_SPACES="$TEST_TMP/My Backups"
  mkdir -p "$BACKUP_SPACES"
  cp -r "$TEST_TMP/server/world" "$WORLD_SPACES"
  ./backup.sh -i "$WORLD_SPACES" -o "$BACKUP_SPACES" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup-full-paths "$BACKUP_SPACES/$TIMESTAMP.tar.gz" "$WORLD_SPACES"
}

test-backup-no-compression () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -a "" -e "" -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar" 
}

test-backup-max-compression () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -a "xz" -e "xz" -l 9e -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.xz" 
}

test-chat-messages () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -c -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_OUTPUT="$(head -n-1 "$TEST_DIR/data/test-chat-messages.txt")"
  ACTUAL_OUTPUT="$(head -n-1 "$TEST_TMP/screen-output")"
  assertEquals "$EXPECTED_OUTPUT" "$ACTUAL_OUTPUT"
}

test-chat-prefix () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -p "Hello" -c -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_OUTPUT="$(head -n-1 "$TEST_DIR/data/test-chat-prefix.txt")"
  ACTUAL_OUTPUT="$(head -n-1 "$TEST_TMP/screen-output")"
  assertEquals "$EXPECTED_OUTPUT" "$ACTUAL_OUTPUT"
}

test-check-help () {
  HELP_HEADER="$(./backup.sh -h)"
  assertEquals "Minecraft Backup" "$(head -n1 <<< "$HELP_HEADER")"
}

test-missing-options () {
  OUTPUT="$(./backup.sh 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertContains "$OUTPUT" "Minecraft screen/tmux/rcon location not specified (use -s)"
  assertContains "$OUTPUT" "Server world not specified"
  assertContains "$OUTPUT" "Backup location not specified"
}

test-restic-and-output-options () {
  OUTPUT="$(./backup.sh -c -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" -r "$TEST_TMP/backups-restic" 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertContains "$OUTPUT" "Both output directory (-o) and restic repo (-r) specified but only one may be used at a time"
}

test-missing-options-suppress-warnings () {
  OUTPUT="$(./backup.sh -q 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertNotContains "$OUTPUT" "Minecraft screen/tmux/rcon location not specified (use -s)"
}

test-invalid-options () {
  OUTPUT="$(./backup.sh -z 2>&1)"
  EXIT_CODE="$?"
  assertEquals 1 "$EXIT_CODE"
  assertContains "$OUTPUT" "Invalid option"
}

test-empty-world-warning () {
  mkdir -p "$TEST_TMP/server/empty-world"
  OUTPUT="$(./backup.sh -v -i "$TEST_TMP/server/empty-world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  assertContains "$OUTPUT" "Backup was not saved!"
}

test-block-size-warning () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -m 10 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  assertContains "$OUTPUT" "is smaller than TOTAL_BLOCK_SIZE"
}

test-bad-input-world () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -m 10 -i "$TEST_TMP/server/notworld" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  assertNotEquals 0 "$EXIT_CODE"
  assertFalse '[ -f '"$TEST_TMP/backups/$TIMESTAMP.tar.gz"' ]'
}

test-nonzero-exit-warning () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -a _BLAH_ -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP" 2>&1)"
  EXIT_CODE="$?"
  assertNotEquals 0 "$EXIT_CODE"
  assertContains "$OUTPUT" "Archive command exited with nonzero exit code"
  assertFalse '[ -f '"$TEST_TMP/backups/$TIMESTAMP.tar.gz"' ]'
}

test-screen-interface () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_CONTENTS=$(echo -e "save-off\nsave-on\nsave-all") 
  SCREEN_CONTENTS="$(cat "$TEST_TMP/screen-output")"
  assertEquals "$EXPECTED_CONTENTS" "$SCREEN_CONTENTS" 
}

test-tmux-interface () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -w tmux -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  EXPECTED_CONTENTS=$(echo -e "save-off\nsave-on\nsave-all") 
  SCREEN_CONTENTS="$(cat "$TEST_TMP/tmux-output")"
  assertEquals "$EXPECTED_CONTENTS" "$SCREEN_CONTENTS" 
}

test-rcon-interface () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -w rcon -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "localhost:$RCON_PORT:$RCON_PASSWORD" -f "$TIMESTAMP"
  EXPECTED_CONTENTS=$(echo -e "save-off\nsave-on\nsave-all") 
  SCREEN_CONTENTS="$(head -n3 "$TEST_TMP/rcon-output")"
  assertEquals "$EXPECTED_CONTENTS" "$SCREEN_CONTENTS" 
}

test-rcon-interface-wrong-password () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -w RCON -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "localhost:$RCON_PORT:wrong$RCON_PASSWORD" -f "$TIMESTAMP" 2>&1)"
  assertContains "$OUTPUT" "Wrong RCON password"
}

test-rcon-interface-not-running () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  OUTPUT="$(./backup.sh -w RCON -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "@!@#:$RCON_PORT:$RCON_PASSWORD" -f "$TIMESTAMP" 2>&1)"
  assertContains "$OUTPUT" "Could not connect"
}

test-sequential-delete () {
  for i in $(seq 0 20); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -d "sequential" -m 30 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  for i in $(seq 20 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -d "sequential" -m 10 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  for i in $(seq 90 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    check-backup "$TIMESTAMP.tar.gz"
  done
  assertEquals 10 "$(find "$TEST_TMP/backups" -type f | wc -l)" 
}

test-restic-sequential-delete () {
  for i in $(seq 0 20); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -d "sequential" -m 10 -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  assertEquals 10 "$(restic list snapshots -r "$TEST_TMP/backups-restic" | wc -l)"
  check-latest-backup-restic
  SNAPSHOTS="$(restic snapshots -r "$TEST_TMP/backups-restic")"
  for i in $(seq 11 20); do
    TIMESTAMP="$(date "+%F %H:%M:%S" --date="2021-01-01 +$i hour")"
    assertContains "$SNAPSHOTS" "$TIMESTAMP" 
  done
  for i in $(seq 0 10); do
    TIMESTAMP="$(date "+%F %H:%M:%S" --date="2021-01-01 +$i hour")"
    assertNotContains "$SNAPSHOTS" "$TIMESTAMP" 
  done
}

test-thinning-delete () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  EXPECTED_TIMESTAMPS=(
    # Weekly

    # Daily (30)
    "2021-01-01_00-00-00"
    "2021-01-02_00-00-00"
    "2021-01-03_00-00-00"

    # Hourly (24)
    "2021-01-03_12-00-00"
    "2021-01-03_13-00-00"
    "2021-01-03_14-00-00"
    "2021-01-03_15-00-00"
    "2021-01-03_16-00-00"
    "2021-01-03_17-00-00"
    "2021-01-03_18-00-00"
    "2021-01-03_19-00-00"
    "2021-01-03_20-00-00"
    "2021-01-04_09-00-00"
    "2021-01-04_10-00-00"
    "2021-01-04_11-00-00"

    # Sub-hourly (16)
    "2021-01-04_12-00-00"
    "2021-01-04_13-00-00"
    "2021-01-04_14-00-00"
    "2021-01-04_15-00-00"
    "2021-01-04_16-00-00"
    "2021-01-04_17-00-00"
    "2021-01-04_18-00-00"
    "2021-01-04_19-00-00"
    "2021-01-04_20-00-00"
    "2021-01-04_21-00-00"
    "2021-01-04_22-00-00"
    "2021-01-04_23-00-00"
    "2021-01-05_00-00-00"
    "2021-01-05_01-00-00"
    "2021-01-05_02-00-00"
    "2021-01-05_03-00-00"
  )
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    check-backup "$TIMESTAMP.tar.gz"
  done
}

test-restic-thinning-delete () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i hour")"
    ./backup.sh -m 70 -i "$TEST_TMP/server/world" -r "$TEST_TMP/backups-restic" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  done
  EXPECTED_TIMESTAMPS=(
    # Weekly

    # Daily (30)
    "2021-01-01 23:00:00"
    "2021-01-02 23:00:00"
    "2021-01-03 23:00:00"

    # Hourly (24)
    "2021-01-04 04:00:00"
    "2021-01-04 05:00:00"
    "2021-01-04 06:00:00"
    "2021-01-04 07:00:00"
    "2021-01-04 08:00:00"
    "2021-01-04 09:00:00"
    "2021-01-04 10:00:00"
    "2021-01-04 11:00:00"

    # Sub-hourly (16)
    "2021-01-04 12:00:00"
    "2021-01-04 13:00:00"
    "2021-01-04 14:00:00"
    "2021-01-04 15:00:00"
    "2021-01-04 16:00:00"
    "2021-01-04 17:00:00"
    "2021-01-04 18:00:00"
    "2021-01-04 19:00:00"
    "2021-01-04 20:00:00"
    "2021-01-04 21:00:00"
    "2021-01-04 22:00:00"
    "2021-01-04 23:00:00"
    "2021-01-05 00:00:00"
    "2021-01-05 01:00:00"
    "2021-01-05 02:00:00"
    "2021-01-05 03:00:00"
  )
  SNAPSHOTS="$(restic snapshots -r "$TEST_TMP/backups-restic")"
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    assertContains "$SNAPSHOTS" "$TIMESTAMP" 
  done
  UNEXPECTED_TIMESTAMPS=(
    "2021-01-01 00:00:00"
    "2021-01-01 01:00:00"
    "2021-01-01 02:00:00"
    "2021-01-02 22:00:00"
    "2021-01-03 22:00:00"
    "2021-01-04 00:00:00"
  )
  for TIMESTAMP in "${UNEXPECTED_TIMESTAMPS[@]}"; do
    assertNotContains "$SNAPSHOTS" "$TIMESTAMP"
  done
}

test-thinning-delete-long () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i day")"
    OUTPUT="$(./backup.sh -v -m 73 -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP")"
  done
  UNEXPECTED_TIMESTAMPS=(
    "2021-01-04_00-00-00"
    "2021-01-05_00-00-00"
    "2021-01-12_00-00-00"
    "2021-01-24_00-00-00"
  )
  for TIMESTAMP in "${UNEXPECTED_TIMESTAMPS[@]}"; do
    assertFalse '[ -f '"$TEST_TMP/backups/$TIMESTAMP.tar.gz"' ]'
  done
  assertEquals 73 "$(find "$TEST_TMP/backups" -type f | wc -l)" 
  EXPECTED_TIMESTAMPS=(
    # Weekly
    "2021-01-11_00-00-00"
    "2021-01-25_00-00-00"
    "2021-01-25_00-00-00"

    # Daily (30)
    "2021-01-31_00-00-00"
    "2021-03-01_00-00-00"

    # Hourly (24)
    "2021-03-02_00-00-00"
    "2021-03-25_00-00-00"

    # Sub-hourly (16)
    "2021-03-26_00-00-00"
    "2021-04-10_00-00-00"
  )
  assertContains "$OUTPUT" "promoted to next block"
  for TIMESTAMP in "${EXPECTED_TIMESTAMPS[@]}"; do
    check-backup "$TIMESTAMP.tar.gz"
  done
}

# shellcheck disable=SC1091
. test/shunit2/shunit2
