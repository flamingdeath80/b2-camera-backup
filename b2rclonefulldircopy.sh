#!/bin/bash

############################################
# CONFIGURATION
############################################

SOURCE_BASE="/home/me/bluecherry-docker/recordings/"
DEST_BASE="b2backup:GLaDOSB2/camera-backups/"
CAMERAS=("000005" "000006")

# Lockfile to prevent overlapping runs
#LOCKFILE="/var/lock/camera-backup.lock"

# Optional: healthcheck URLs (set to empty to disable)
HEALTHCHECK_OK=""
HEALTHCHECK_FAIL=""

############################################
# LOCKFILE PROTECTION
############################################

#exec 200>"$LOCKFILE"
#flock -n 200 || {
#    echo "[$(date)] Backup already running, exiting."
#    exit 1
#}

############################################
# MAIN BACKUP LOOP
############################################

for CAM in "${CAMERAS[@]}"; do
    LOG_FILE="/var/log/camera-${CAM}.log"
    HEARTBEAT="/var/log/camera-${CAM}.lastok"

    echo "[$(date)] Starting backup for camera $CAM" | tee -a "$LOG_FILE"

    rclone copy "$SOURCE_BASE" "$DEST_BASE" \
        --min-age 10s \
        --max-age 1h \
        --include "*/$CAM/*.mp4" \
        --transfers 4 \
        --checkers 8 \
        --b2-chunk-size 96M \
        --b2-upload-cutoff 200M \
        --log-level INFO \
        --log-file "$LOG_FILE" \
        --stats 1m \
        --stats-log-level NOTICE

    if [ $? -eq 0 ]; then
        echo "[$(date)] Camera $CAM backup completed successfully" | tee -a "$LOG_FILE"
        touch "$HEARTBEAT"

        # Optional success ping
        [ -n "$HEALTHCHECK_OK" ] && curl -fsS -m 10 "$HEALTHCHECK_OK" >/dev/null 2>&1
    else
        echo "[$(date)] Camera $CAM backup FAILED" | tee -a "$LOG_FILE"

        # Optional failure ping
        [ -n "$HEALTHCHECK_FAIL" ] && curl -fsS -m 10 "$HEALTHCHECK_FAIL" >/dev/null 2>&1
    fi
done

echo "[$(date)] All camera backups finished."