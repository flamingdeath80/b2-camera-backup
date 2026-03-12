# Bluecherry DVR → Backblaze B2 Backup Scripts

A set of bash scripts to back up [Bluecherry DVR](https://www.bluecherrydvr.com/) recordings (MP4 + JPG files) to a private [Backblaze B2](https://www.backblaze.com/b2/cloud-storage.html) bucket using [rclone](https://rclone.org/), with automated retention management.

Bluecherry splits recordings into 15-minute MP4 segments. These scripts are designed around that structure.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `b2-full-copy.sh` | One-time full backup of all recordings |
| `b2-dynamic-copy.sh` | Incremental daily backup across all camera channels (designed for cron) |
| `b2-retention.sh` | Deletes files older than 30 days from B2 |

---

## Prerequisites

- [rclone](https://rclone.org/install/) installed and configured with two B2 remotes (see below)
- A Backblaze B2 bucket
- Bluecherry DVR writing recordings to the local filesystem

### Configuring rclone for B2

These scripts use **two separate rclone remotes**, each backed by a B2 application key with different permission scopes. This follows the principle of least privilege — the backup scripts cannot delete files, and only the retention script can.

Run `rclone config` twice to create both remotes:

| Remote name | Required B2 permissions | Used by |
|-------------|------------------------|---------|
| `b2-readonly` | `listFiles`, `readFiles`, `writeFiles` | `b2-full-copy.sh`, `b2-dynamic-copy.sh` |
| `b2-readwrite` | `listFiles`, `readFiles`, `writeFiles`, `deleteFiles` | `b2-retention.sh` |

> Create separate application keys in the Backblaze dashboard (**Buckets → App Keys → Add a New Application Key**), one per remote, with the appropriate permissions for each.

---

## Configuration

Each script has a configuration block near the top. Edit these variables before use.

### `b2-full-copy.sh`

```bash
SOURCE_BASE="/home/me/bluecherry-docker/recordings/"  # Local Bluecherry recordings path
RCLONE_REMOTE="b2-readonly"                           # rclone remote (no delete permissions)
B2_BUCKET="GLaDOSB2"                                  # B2 bucket name
B2_DEST_PATH="camera-backups"                         # Path within the bucket
LOG_FILE="/var/log/b2-fullbackup.log"
```

### `b2-dynamic-copy.sh`

```bash
SOURCE_BASE="/home/me/bluecherry-docker/recordings"   # Local Bluecherry recordings path
RCLONE_REMOTE="b2-readonly"                           # rclone remote (no delete permissions)
B2_BUCKET="GLaDOSB2"                                  # B2 bucket name
B2_DEST_PATH="camera-backups"                         # Path within the bucket
LOG_FILE="/var/log/b2-backup.log"

# Add or remove channel IDs to match your Bluecherry camera setup
CAMERA_CHANNELS=(
    "000001"
    "000002"
    "000005"
)

# Optional healthcheck URLs (leave empty to disable — e.g. healthchecks.io)
HEALTHCHECK_OK=""
HEALTHCHECK_FAIL=""
```

### `b2-retention.sh`

```bash
RCLONE_REMOTE="b2-readwrite"      # rclone remote (requires delete permissions)
B2_BUCKET="GLaDOSB2"              # B2 bucket name
B2_DEST_PATH="camera-backups"     # Path within the bucket — must match copy scripts
MAX_AGE="30d"                     # Retention period
LOG_FILE="/var/log/b2retention.log"
```

---

## Usage

### Initial Full Backup

Run once to seed the B2 bucket with all existing recordings:

```bash
chmod +x b2-full-copy.sh
./b2-full-copy.sh
```

This copies the entire `SOURCE_BASE` directory tree to B2. It can safely be re-run — rclone will skip files that are already present and unchanged.

### Incremental Daily Backup

Run on a schedule (every 15–30 minutes via cron) to keep B2 up to date:

```bash
chmod +x b2-dynamic-copy.sh
./b2-dynamic-copy.sh
```

The script iterates over every channel defined in `CAMERA_CHANNELS` and backs up each one for the current date. The `--min-age 10s` flag ensures rclone skips any files still being written by Bluecherry (i.e. the current active 15-minute segment), so only completed segments are uploaded.

It also includes a **midnight boundary guard**: during the `00:xx` hour, the previous day's directories are backed up across all channels to catch any segments that were still being written when the date rolled over.

**Recommended cron entry** (every 15 minutes):

```
*/15 * * * * /home/me/b2-dynamic-copy.sh
```

### Retention Cleanup

Run daily to purge recordings older than 30 days from B2 and remove empty directories:

```bash
chmod +x b2-retention.sh
./b2-retention.sh
```

The script uses a lock file (`/tmp/b2retention.lock`) to prevent overlapping runs. It performs two steps:

1. Deletes all files older than `MAX_AGE` from the configured B2 path
2. Removes any empty directories left behind

**Recommended cron entry** (daily at 3am):

```
0 3 * * * /home/me/b2-retention.sh
```

---

## Directory Structure

The scripts mirror Bluecherry's on-disk layout in B2:

```
camera-backups/
└── YYYY/
    └── MM/
        └── DD/
            ├── 000001/       # Camera channel ID
            │   ├── *.mp4
            │   └── *.jpg
            ├── 000002/
            │   ├── *.mp4
            │   └── *.jpg
            └── 000005/
                ├── *.mp4
                └── *.jpg
```

Channel IDs correspond to Bluecherry's internal camera numbering. Add all of your active channel IDs to the `CAMERA_CHANNELS` array in `b2-dynamic-copy.sh`.

---

## Logs

| Script | Default log path |
|--------|-----------------|
| `b2-full-copy.sh` | `/var/log/b2-fullbackup.log` |
| `b2-dynamic-copy.sh` | `/var/log/b2-backup.log` |
| `b2-retention.sh` | `/var/log/b2retention.log` |

All scripts append timestamped entries to their log files. rclone's own output is also written to the same log.

---

## rclone Transfer Settings

The copy scripts use the following rclone flags, tuned for B2:

| Flag | Value | Purpose |
|------|-------|---------|
| `--transfers` | `4` | Parallel file uploads |
| `--checkers` | `8` | Parallel file comparison checks |
| `--b2-chunk-size` | `96M` | Multipart chunk size |
| `--b2-upload-cutoff` | `200M` | Switch to multipart above this size |
| `--min-age` | `10s` | Skip files modified in the last 10 seconds, preventing upload of segments still being written by Bluecherry |

Adjust these based on your available bandwidth and B2 tier limits.

---

## License

MIT — use and modify freely.
