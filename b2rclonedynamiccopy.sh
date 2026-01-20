#!/bin/bash

# Get the full date and time string
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")

# Set Internal Field Separator (IFS) to hyphen and read into variables
IFS='-' read -r YYYY MM DD HH MIN SS <<< "$TIMESTAMP"

# Configuration
SOURCE_DIR=/home/me/bluecherry-docker/recordings/$YYYY/$MM/$DD/000005/
B2_REMOTE=b2backup:GLaDOSB2/camera-backups/$YYYY/$MM/$DD/000005/
LOG_FILE="/var/log/camera05-backup.log"

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting camera backup..."

# Copy to B2 (only uploads new/changed files)
rclone copy "$SOURCE_DIR" "$B2_REMOTE" \
    --transfers 4 \
    --min-age 10s \
    --checkers 8 \
    --b2-chunk-size 96M \
    --b2-upload-cutoff 200M \
    --log-level INFO \
    --log-file "$LOG_FILE" \
    --stats 1m \
    --stats-log-level NOTICE

if [ $? -eq 0 ]; then
    log "Backup completed successfully"
else
    log "Backup failed with errors"
fi