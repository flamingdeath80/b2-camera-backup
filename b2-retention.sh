#!/usr/bin/env bash
# =============================================================================
# Backblaze B2 Cleanup Script
#
# Deletes files older than 30 days from the B2 bucket, then removes
# any empty directories left behind.
#
# Usage:
#   chmod +x cleanup_b2.sh
#   ./cleanup_b2.sh
#
# Cron example (run daily at 3am):
#   0 3 * * * /home/me/cleanup_b2.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — match these to your sync script
# ---------------------------------------------------------------------------
RCLONE_REMOTE="rclone-config-name-here"
B2_BUCKET="b2-bucket-name-here"
B2_DEST_PATH="b2-bucket-path-here"                             # must match sync script
MAX_AGE="retention-age-here"

LOG_FILE="/var/log/b2retention.log"  # set to "" for stdout only
LOCK_FILE="/tmp/b2retention.lock"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
    echo "$msg"
    [[ -n "${LOG_FILE}" ]] && echo "$msg" >> "${LOG_FILE}" 2>/dev/null || true
}

log_error() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*"
    echo "$msg" >&2
    [[ -n "${LOG_FILE}" ]] && echo "$msg" >> "${LOG_FILE}" 2>/dev/null || true
}

cleanup() {
    rm -rf "${LOCK_FILE}"
}
trap cleanup EXIT

# Acquire lock
if ! mkdir "${LOCK_FILE}" 2>/dev/null; then
    if [[ -f "${LOCK_FILE}/pid" ]]; then
        old_pid=$(<"${LOCK_FILE}/pid")
        if kill -0 "${old_pid}" 2>/dev/null; then
            log "Another instance (PID ${old_pid}) is already running. Exiting."
            exit 0
        else
            rm -rf "${LOCK_FILE}"
            mkdir "${LOCK_FILE}"
        fi
    else
        rm -rf "${LOCK_FILE}"
        mkdir "${LOCK_FILE}"
    fi
fi
echo $$ > "${LOCK_FILE}/pid"

# ---------------------------------------------------------------------------
# Build remote path
# ---------------------------------------------------------------------------
REMOTE_PATH="${RCLONE_REMOTE}:${B2_BUCKET}"
[[ -n "${B2_DEST_PATH}" ]] && REMOTE_PATH="${REMOTE_PATH}/${B2_DEST_PATH}"

# ---------------------------------------------------------------------------
# Step 1: Delete files older than MAX_AGE
# ---------------------------------------------------------------------------
log "=== B2 Cleanup starting (PID $$) ==="
log "Deleting files older than ${MAX_AGE} from ${REMOTE_PATH}"

rclone delete \
    "${REMOTE_PATH}" \
    --min-age "${MAX_AGE}" \
    --log-level INFO \
    --low-level-retries 1 \
    --retries 1 \
    --retries-sleep 0 \
    2>&1 | while IFS= read -r line; do
        [[ -n "${line}" ]] && log "  rclone: ${line}"
    done

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "rclone delete failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Remove empty directories
# ---------------------------------------------------------------------------
log "Removing empty directories from ${REMOTE_PATH}"

rclone rmdirs \
    "${REMOTE_PATH}" \
    --log-level INFO \
    2>&1 | while IFS= read -r line; do
        [[ -n "${line}" ]] && log "  rclone: ${line}"
    done

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "rclone rmdirs failed"
    exit 1
fi

log "=== B2 Cleanup completed ==="
