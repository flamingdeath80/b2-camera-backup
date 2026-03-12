#!/bin/bash

SOURCE_BASE="/path/to/bluecherry-docker/recordings/"
DEST_BASE="rclone-config-name:B2-bucket-name/b2-bucket-path/"
LOG_FILE="/var/log/b2-fullbackup.log"

    rclone copy "$SOURCE_BASE" "$DEST_BASE" \
        --min-age 10s \
        --transfers 4 \
        --checkers 8 \
        --b2-chunk-size 96M \
        --b2-upload-cutoff 200M \
        --log-level INFO \
        --log-file "$LOG_FILE" \
        --stats 1m \
        --stats-log-level NOTICE

    if [ $? -eq 0 ]; then
        echo "[$(date)] Cameras backup completed successfully" | tee -a "$LOG_FILE"
    else
        echo "[$(date)] Cameras backup FAILED" | tee -a "$LOG_FILE"
    fi

echo "[$(date)] All camera backups finished."
