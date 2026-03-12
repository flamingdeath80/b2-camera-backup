#!/bin/bash

# =============================================================================
# Bluecherry DVR → Backblaze B2 Incremental Backup
#
# Backs up recordings for the current date across all configured camera
# channels. During the midnight hour (00:xx), also backs up the previous
# day to capture any 15-minute segments still being written when the date
# rolled over.
#
# Designed to be run via cron every 15–30 minutes:
#   */15 * * * * /home/me/b2-dynamic-copy.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

LOG_FILE="/var/log/b2-backup.log"

SOURCE_BASE="/home/me/bluecherry-docker/recordings"

# rclone remote configured with listFiles, readFiles, writeFiles permissions
# (no delete permissions required for backup)
RCLONE_REMOTE="b2-readonly"
B2_BUCKET="GLaDOSB2"
B2_DEST_PATH="camera-backups"

# Camera channel directories to back up.
# Add or remove channel IDs to match your Bluecherry setup.
CAMERA_CHANNELS=(
    "000001"
)

# Optional: healthcheck URLs (leave empty to disable)
HEALTHCHECK_OK=""
HEALTHCHECK_FAIL=""

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Backup a single channel for a given date
# -----------------------------------------------------------------------------
backup_channel_date() {
    local YYYY=$1 MM=$2 DD=$3 CHANNEL=$4

    local SOURCE_DIR="${SOURCE_BASE}/${YYYY}/${MM}/${DD}/${CHANNEL}/"
    local B2_DEST="${RCLONE_REMOTE}:${B2_BUCKET}/${B2_DEST_PATH}/${YYYY}/${MM}/${DD}/${CHANNEL}/"

    # Skip silently if this camera has no recordings for this date
    if [ ! -d "$SOURCE_DIR" ]; then
        log "  [${CHANNEL}] Source directory does not exist, skipping."
        return 0
    fi

    log "  [${CHANNEL}] Backing up $SOURCE_DIR -> $B2_DEST"

    rclone copy "$SOURCE_DIR" "$B2_DEST" \
        --transfers 4 \
        --min-age 10s \
        --checkers 8 \
        --b2-chunk-size 96M \
        --b2-upload-cutoff 200M \
        --log-level INFO \
        --log-file "$LOG_FILE" \
        --stats 1m \
        --stats-log-level NOTICE

    return $?
}

# -----------------------------------------------------------------------------
# Backup all channels for a given date
# -----------------------------------------------------------------------------
backup_date() {
    local YYYY=$1 MM=$2 DD=$3
    local STATUS=0

    log "Backing up date: ${YYYY}/${MM}/${DD} (${#CAMERA_CHANNELS[@]} channel(s))"

    for CHANNEL in "${CAMERA_CHANNELS[@]}"; do
        backup_channel_date "$YYYY" "$MM" "$DD" "$CHANNEL" || STATUS=1
    done

    return $STATUS
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

log "Starting camera backup..."

OVERALL_STATUS=0

# Get current time components
IFS='-' read -r YYYY MM DD HH MIN SS <<< "$(date +"%Y-%m-%d-%H-%M-%S")"

# During the midnight hour (00:xx), also back up yesterday to catch any
# 15-minute segments that were still being written when the date rolled over
if [ "$HH" == "00" ]; then
    IFS='-' read -r PYYYY PMM PDD _ _ _ <<< "$(date -d 'yesterday' +"%Y-%m-%d-%H-%M-%S")"
    log "Midnight hour detected — also backing up previous day (${PYYYY}/${PMM}/${PDD})"
    backup_date "$PYYYY" "$PMM" "$PDD" || OVERALL_STATUS=1
fi

# Back up today
backup_date "$YYYY" "$MM" "$DD" || OVERALL_STATUS=1

if [ $OVERALL_STATUS -eq 0 ]; then
    log "Backup completed successfully"
    [ -n "$HEALTHCHECK_OK" ] && curl -fsS -m 10 "$HEALTHCHECK_OK" >/dev/null 2>&1
else
    log "Backup finished with errors"
    [ -n "$HEALTHCHECK_FAIL" ] && curl -fsS -m 10 "$HEALTHCHECK_FAIL" >/dev/null 2>&1
fi
