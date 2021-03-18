#!/usr/bin/env bash

# Helper functions

TEST_DIR="test"
TEST_TMP="$TEST_DIR/tmp"
SCREEN_TMP="tmp-screen"
RCON_PORT="8088"
RCON_PASSWORD="supersecret"
setUp () {
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP/server/world"
  mkdir -p "$TEST_TMP/backups"
  echo "file1" > "$TEST_TMP/server/world/file1.txt"
  echo "file2" > "$TEST_TMP/server/world/file2.txt"
  echo "file3" > "$TEST_TMP/server/world/file3.txt"

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
  if [ -d "$1" ]; then
    for FILE in "$1"/*; do
      assert-equals-directory "$FILE" "$2/${FILE##$1}"
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
  assert-equals-directory "$WORLD_DIR" "$TEST_TMP/restored"
  rm -rf "$TEST_TMP/restored"
}

check-backup () {
  BACKUP_ARCHIVE="$1"
  check-backup-full-paths "$TEST_TMP/backups/$BACKUP_ARCHIVE" "$TEST_TMP/server/world"
}

# Tests

test-backup-defaults () {
  TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01")"
  ./backup.sh -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP"
  check-backup "$TIMESTAMP.tar.gz"
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
  assertContains "$OUTPUT" "Backup directory not specified"
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
  assert-equals-directory "$WORLD_DIR/file1.txt" "$TEST_TMP/restored/file1.txt"
  assert-equals-directory "$WORLD_DIR/file2.txt" "$TEST_TMP/restored/file2.txt"
  assert-equals-directory "$WORLD_DIR/file3.txt" "$TEST_TMP/restored/file3.txt"
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

test-thinning-delete-long () {
  for i in $(seq 0 99); do
    TIMESTAMP="$(date +%F_%H-%M-%S --date="2021-01-01 +$i day")"
    OUTPUT="$(./backup.sh -v -i "$TEST_TMP/server/world" -o "$TEST_TMP/backups" -s "$SCREEN_TMP" -f "$TIMESTAMP")"
  done
  UNEXPECTED_TIMESTAMPS=(
    "2021-01-05_00-00-00"
    "2021-01-12_00-00-00"
    "2021-01-24_00-00-00"
  )
  for TIMESTAMP in "${UNEXPECTED_TIMESTAMPS[@]}"; do
    assertFalse '[ -f '"$TEST_TMP/backups/$TIMESTAMP.tar.gz"' ]'
  done
  assertEquals 74 "$(find "$TEST_TMP/backups" -type f | wc -l)" 
  EXPECTED_TIMESTAMPS=(
    # Weekly
    "2021-01-04_00-00-00"
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
