# Backblaze B2 Camera Backup Scripts

A collection of bash scripts for backing up BluecherryDVR security camera footage to Backblaze B2 storage using rclone.

## Overview

These scripts provide automated offsite backup of security camera recordings (MP4 and JPG files) from a Bluecherry DVR system to Backblaze B2 cloud storage. The scripts are designed to work with read/write-only API credentials, relying on Backblaze lifecycle policies for retention management. These scripts can be configured for a different use case however

## Scripts

### 1. b2rclonefulldircopy.sh - Full Directory Backup

This script performs a comprehensive backup of all camera footage by traversing the entire source directory structure.

**Use Case:** Suitable for initial backups or when you need to ensure all historical footage is backed up.

**Features:**
- Backs up multiple cameras in a single run
- Processes the entire directory tree
- Only uploads files between 10 seconds and 1 hour old (configurable)
- Includes lockfile protection to prevent overlapping runs (commented out by default)
- Optional healthcheck integration for monitoring
- Per-camera logging

**Pros:**
- Ensures complete backup coverage
- Handles multiple cameras automatically

**Cons:**
- Higher API call usage due to full directory traversal
- Increased cost compared to targeted backups

### 2. b2rclonedynamiccopy.sh - Date-Based Dynamic Backup

This script performs a targeted backup of only today's footage by constructing the path dynamically based on the current date.

**Use Case:** Ideal for daily scheduled backups where you only need to sync today's recordings.

**Features:**
- Automatically constructs paths using current date
- Minimal API calls by targeting specific directories
- Efficient for daily scheduled runs
- Single camera per script instance

**Pros:**
- Lower API call count
- Reduced costs
- Faster execution time

**Cons:**
- Requires separate script instances or modifications for multiple cameras
- Only backs up current day's footage

## Prerequisites

- **rclone** installed and configured
- **Backblaze B2** account with a bucket configured
- **Bluecherry** DVR system (or similar with date-based folder structure)

## Configuration

### Backblaze B2 Setup

1. Create a Backblaze B2 bucket
2. Generate an application key with **read and write permissions only** (no delete)
3. Configure a lifecycle policy on the bucket to manage retention and prevent unlimited growth

### Rclone Setup

Configure rclone with your Backblaze B2 credentials:

```bash
rclone config
```

When configuring, note the following structure used in these scripts:
- **Remote name:** `b2backup` (the authorized account name in rclone)
- **Bucket name:** `GLaDOSB2` (your Backblaze bucket name)
- **Folder path:** `camera-backups/` (folder in the root of the bucket)

### Script Configuration

#### b2rclonefulldircopy.sh

Edit the following variables:

```bash
SOURCE_BASE="/home/me/bluecherry-docker/recordings/"
DEST_BASE="b2backup:GLaDOSB2/camera-backups/"
CAMERAS=("000005" "000006")  # Camera prefixes/identifiers
```

Optional configurations:
- Uncomment lockfile lines to prevent concurrent runs
- Set `HEALTHCHECK_OK` and `HEALTHCHECK_FAIL` URLs for monitoring integration

#### b2rclonedynamiccopy.sh

Edit the following variables:

```bash
SOURCE_DIR=/home/me/bluecherry-docker/recordings/$YYYY/$MM/$DD/000005/
B2_REMOTE=b2backup:GLaDOSB2/camera-backups/$YYYY/$MM/$DD/000005/
LOG_FILE="/var/log/camera05-backup.log"
```

Note: The camera ID (e.g., `000005`) is hardcoded and should match your camera folder or prefix identifier.

## Directory Structure

The scripts expect the following source directory structure:

```
/home/me/bluecherry-docker/recordings/
├── YYYY/
│   ├── MM/
│   │   ├── DD/
│   │   │   ├── 000005/  # Camera 1
│   │   │   │   ├── *.mp4
│   │   │   │   └── *.jpg
│   │   │   └── 000006/  # Camera 2
│   │   │       ├── *.mp4
│   │   │       └── *.jpg
```

## Usage

### Make Scripts Executable

```bash
chmod +x b2rclonefulldircopy.sh
chmod +x b2rclonedynamiccopy.sh
```

### Manual Execution

```bash
# Full directory backup
./b2rclonefulldircopy.sh

# Daily targeted backup
./b2rclonedynamiccopy.sh
```

### Automated Execution (Cron)

For daily backups using the dynamic script, below is an example cron frequency, you can change this to suite your usecase:

```bash
# Run every day at 2:00 AM
0 2 * * * /path/to/b2rclonedynamiccopy.sh

# Run every 15 minutes (for near real-time backup)
*/15 * * * * /path/to/b2rclonedynamiccopy.sh
```

For weekly full backups (again, change as desired):

```bash
# Run every Sunday at 3:00 AM
0 3 * * 0 /path/to/b2rclonefulldircopy.sh
```

## Rclone Parameters Explained

Both scripts use optimized rclone parameters:

- `--transfers 4` - Upload 4 files simultaneously
- `--checkers 8` - Check 8 files simultaneously for changes
- `--b2-chunk-size 96M` - Upload chunks of 96MB
- `--b2-upload-cutoff 200M` - Use multi-part uploads for files over 200MB
- `--min-age 10s` - Only upload files older than 10 seconds (prevents uploading files still being written)
- `--max-age 1h` - Only upload files younger than 1 hour (full script only)
- `--log-level INFO` - Detailed logging
- `--stats 1m` - Show statistics every minute

## Logging

Logs are written to:
- **Full script:** `/var/log/camera-{CAMERA_ID}.log`
- **Dynamic script:** `/var/log/camera05-backup.log` (or your configured path)

View logs in real-time:

```bash
tail -f /var/log/camera-000005.log
```

## Monitoring

The full directory script includes optional healthcheck integration. Set the following variables to enable:

```bash
HEALTHCHECK_OK="https://hc-ping.com/your-uuid"
HEALTHCHECK_FAIL="https://hc-ping.com/your-uuid/fail"
```

The script will ping these URLs on success or failure, allowing integration with services like Healthchecks.io.

## Security Considerations

- **API Permissions:** Scripts use read/write-only credentials (no delete permission)
- **Retention:** Managed via Backblaze lifecycle policies, not via rclone
- **Lockfile:** Prevent concurrent runs by uncommenting lockfile protection
- **Credentials:** Ensure rclone config file has appropriate permissions (600)

## Cost Optimization

The dynamic script (`b2rclonedynamiccopy.sh`) is recommended for daily scheduled backups as it:
- Makes fewer API calls
- Traverses only today's directory structure
- Reduces transaction costs

Use the full script (`b2rclonefulldircopy.sh`) sparingly for:
- Initial backups
- Verification runs
- Recovery from backup gaps

## Troubleshooting

### Files Not Uploading

- Check `--min-age` setting - files might be too new
- Verify source directory exists and contains files
- Check rclone configuration with `rclone config show`

### High API Costs

- Ensure you're using the dynamic script for daily runs
- Verify `--max-age` is set appropriately to avoid re-checking old files
- Consider adjusting the cron schedule to run less frequently

### Permission Errors

- Verify rclone remote has write permissions to the bucket
- Check that the API key is valid and not expired
- Ensure the bucket exists and is accessible

## License

MIT License - feel free to modify and use as needed.

## Contributing

Contributions, issues, and feature requests are welcome!

## Acknowledgments

- Built with [rclone](https://rclone.org/)
- Designed for [Bluecherry](https://www.bluecherrydvr.com/) DVR systems
- Designed for [Backblaze B2](www.backblaze.com/) Cloud storage
