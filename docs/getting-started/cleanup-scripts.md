# Cleanup Scripts User Guide

This guide provides step-by-step instructions for using the EEMT job data cleanup scripts to manage disk space and maintain system performance.

## Quick Start

The fastest way to get started with automated cleanup:

```bash
# Navigate to web interface directory
cd web-interface/

# Set up automated daily cleanup (user-level)
./setup_cleanup_cron.sh --user --method cron

# Test cleanup in dry-run mode
python cleanup_jobs.py --dry-run
```

!!! success "Default Configuration"
    The default settings work well for most users:
    - Successful job data kept for 7 days
    - Failed job data removed after 12 hours
    - Runs daily at 2:00 AM local time
    - Job configurations always preserved

## Using the Cleanup Script

### Basic Commands

#### Manual Cleanup

Run cleanup immediately with default settings:

```bash
python cleanup_jobs.py
```

Expected output:
```
2024-01-20 14:30:15 - cleanup_jobs - INFO - Starting EEMT job data cleanup process
2024-01-20 14:30:15 - cleanup_jobs - INFO - Found 3 successful jobs for data cleanup
2024-01-20 14:30:15 - cleanup_jobs - INFO - Found 1 failed jobs for complete deletion
2024-01-20 14:30:16 - cleanup_jobs - INFO - Deleted results directory: results/job-20240113-095423 (8234.5 MB)
2024-01-20 14:30:17 - cleanup_jobs - INFO - === CLEANUP SUMMARY ===
2024-01-20 14:30:17 - cleanup_jobs - INFO - Successful jobs processed: 3
2024-01-20 14:30:17 - cleanup_jobs - INFO - Failed jobs processed: 1
2024-01-20 14:30:17 - cleanup_jobs - INFO - Total disk space freed: 15678.9 MB
```

#### Preview Mode (Dry Run)

See what would be deleted without making changes:

```bash
python cleanup_jobs.py --dry-run
```

Sample output:
```
2024-01-20 14:35:00 - cleanup_jobs - INFO - === DRY RUN MODE - NO CHANGES WILL BE MADE ===
2024-01-20 14:35:00 - cleanup_jobs - INFO - [DRY RUN] Would delete results directory: results/job-20240113-095423 (8234.5 MB)
2024-01-20 14:35:00 - cleanup_jobs - INFO - [DRY RUN] Would delete uploaded DEM: uploads/job-20240113-095423_dem.tif (125.3 MB)
2024-01-20 14:35:00 - cleanup_jobs - INFO - [DRY RUN] Summary: Would clean 3 jobs, freeing ~15.3 GB
```

#### Custom Retention Periods

Override default retention settings:

```bash
# Keep successful jobs for 14 days instead of 7
python cleanup_jobs.py --success-retention-days 14

# Remove failed jobs after 24 hours instead of 12
python cleanup_jobs.py --failed-retention-hours 24

# Combine both
python cleanup_jobs.py --success-retention-days 14 --failed-retention-hours 24
```

### Advanced Options

#### Verbose Output

Get detailed information about each operation:

```bash
python cleanup_jobs.py --verbose
```

Verbose output includes:
- Individual file deletions
- Directory sizes
- Database operations
- Timing information

#### Custom Paths

If your installation uses non-standard paths:

```bash
python cleanup_jobs.py \
    --base-dir /custom/eemt/web-interface \
    --verbose
```

#### Combining Options

Use multiple options together:

```bash
python cleanup_jobs.py \
    --dry-run \
    --verbose \
    --success-retention-days 3 \
    --failed-retention-hours 6
```

### Understanding Output

#### Cleanup Summary

After each run, you'll see a summary:

```
=== CLEANUP SUMMARY ===
Successful jobs processed: 5      # Jobs older than 7 days with data removed
Failed jobs processed: 2          # Failed jobs older than 12 hours fully removed
Total disk space freed: 25678.9 MB   # Actual disk space recovered
Job configs preserved: 5          # Job records kept in database
Job configs deleted: 2            # Failed job records removed
Errors encountered: 0             # Any errors during cleanup
```

#### Log Files

Cleanup operations are logged to:
- Console output (when run manually)
- `cleanup_jobs.log` (in the script directory)
- System logs (when run via cron/systemd)

#### JSON Summary Files

Each cleanup creates a detailed JSON summary:
```bash
# View latest cleanup summary
ls -lt cleanup_summary_*.json | head -1

# Pretty-print the summary
python -m json.tool cleanup_summary_20240120_143017.json
```

## Setting Up Automated Cleanup

### Using the Setup Script

The `setup_cleanup_cron.sh` script automates the scheduling configuration:

#### Install with Cron (Recommended)

```bash
# User-level installation (recommended)
./setup_cleanup_cron.sh --user --method cron

# System-wide installation (requires sudo)
sudo ./setup_cleanup_cron.sh --system --method cron
```

#### Install with Systemd

For systems using systemd:

```bash
# User-level systemd timer
./setup_cleanup_cron.sh --user --method systemd

# System-wide systemd timer (requires sudo)
sudo ./setup_cleanup_cron.sh --system --method systemd
```

#### Verify Installation

After installation, verify the schedule:

```bash
# For cron
crontab -l | grep cleanup_jobs

# For systemd
systemctl --user status eemt-cleanup.timer
```

### Manual Cron Configuration

If you prefer manual configuration:

1. Open crontab editor:
   ```bash
   crontab -e
   ```

2. Add cleanup schedule (choose one):
   ```cron
   # Daily at 2:00 AM
   0 2 * * * cd /path/to/web-interface && python3 cleanup_jobs.py >> cleanup_jobs.log 2>&1
   
   # Every 6 hours
   0 */6 * * * cd /path/to/web-interface && python3 cleanup_jobs.py
   
   # Weekly on Sunday at 3:00 AM
   0 3 * * 0 cd /path/to/web-interface && python3 cleanup_jobs.py
   
   # Twice daily at 2:00 AM and 2:00 PM
   0 2,14 * * * cd /path/to/web-interface && python3 cleanup_jobs.py
   ```

3. Save and exit (usually Ctrl+X in nano)

### Manual Systemd Configuration

For systemd timer setup:

1. Create service file (`~/.config/systemd/user/eemt-cleanup.service`):
   ```ini
   [Unit]
   Description=EEMT Job Data Cleanup Service
   After=network.target
   
   [Service]
   Type=oneshot
   WorkingDirectory=/path/to/web-interface
   ExecStart=/usr/bin/python3 /path/to/web-interface/cleanup_jobs.py
   StandardOutput=journal
   StandardError=journal
   
   [Install]
   WantedBy=default.target
   ```

2. Create timer file (`~/.config/systemd/user/eemt-cleanup.timer`):
   ```ini
   [Unit]
   Description=Daily EEMT Job Cleanup Timer
   
   [Timer]
   OnCalendar=daily
   OnCalendar=*-*-* 02:00:00
   Persistent=true
   
   [Install]
   WantedBy=timers.target
   ```

3. Enable and start timer:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable eemt-cleanup.timer
   systemctl --user start eemt-cleanup.timer
   ```

## Configuring Retention Periods

### Environment Variables

Set system-wide retention periods:

```bash
# Add to ~/.bashrc or /etc/environment
export EEMT_SUCCESS_RETENTION_DAYS=14    # Keep successful jobs for 2 weeks
export EEMT_FAILED_RETENTION_HOURS=24    # Keep failed jobs for 1 day

# Apply changes
source ~/.bashrc
```

### Per-Execution Override

Override settings for a single run:

```bash
# Quick cleanup - 3 day retention
python cleanup_jobs.py --success-retention-days 3

# Conservative cleanup - 30 day retention
python cleanup_jobs.py --success-retention-days 30
```

### Configuration File

For complex setups, create `cleanup_config.yaml`:

```yaml
# Retention settings
retention:
  successful_jobs:
    days: 7
    keep_logs: true
  failed_jobs:
    hours: 12
    keep_error_logs: true

# Performance settings
performance:
  batch_size: 50
  verbose: true

# Notification settings (optional)
notifications:
  email_on_completion: admin@example.com
  slack_webhook: https://hooks.slack.com/services/XXX
```

Load configuration:
```python
# In a custom script
import yaml

with open('cleanup_config.yaml', 'r') as f:
    config = yaml.safe_load(f)

retention_days = config['retention']['successful_jobs']['days']
```

## Monitoring Cleanup Operations

### Viewing Logs

#### Real-time Monitoring

Watch cleanup progress in real-time:

```bash
# Follow log file
tail -f cleanup_jobs.log

# Watch with highlighting
tail -f cleanup_jobs.log | grep --color=auto -E 'ERROR|WARNING|$'
```

#### Historical Logs

Review past cleanup operations:

```bash
# View last 50 lines
tail -n 50 cleanup_jobs.log

# Search for specific job
grep "job-20240115-123456" cleanup_jobs.log

# Count freed space over time
grep "Total disk space freed" cleanup_jobs.log | awk '{sum+=$7} END {print sum/1024 " GB total"}'
```

### Systemd Journal

If using systemd timers:

```bash
# View recent cleanup runs
journalctl --user -u eemt-cleanup.service -n 50

# Follow live
journalctl --user -u eemt-cleanup.service -f

# View since yesterday
journalctl --user -u eemt-cleanup.service --since yesterday
```

### Cleanup Metrics

Monitor cleanup effectiveness:

```bash
# Check disk usage trend
df -h /path/to/results | grep -v Filesystem

# Count jobs by status
sqlite3 jobs.db "SELECT status, COUNT(*) FROM jobs GROUP BY status;"

# View jobs pending cleanup
sqlite3 jobs.db "
SELECT id, status, datetime(completed_at) as completed, 
       CAST((julianday('now') - julianday(completed_at)) AS INTEGER) as days_old
FROM jobs 
WHERE status IN ('completed', 'failed') 
  AND completed_at IS NOT NULL
  AND data_cleaned_at IS NULL
ORDER BY completed_at;"
```

## Troubleshooting

### Common Issues and Solutions

#### Issue: Cleanup Not Running Automatically

**Check cron job:**
```bash
# List current cron jobs
crontab -l

# Check cron service
systemctl status cron  # or 'crond' on some systems

# View cron logs
grep CRON /var/log/syslog | tail -20
```

**Check systemd timer:**
```bash
# Timer status
systemctl --user status eemt-cleanup.timer

# List timers
systemctl --user list-timers

# Check next run time
systemctl --user list-timers eemt-cleanup.timer
```

#### Issue: Permission Denied Errors

```bash
# Check ownership
ls -la uploads/ results/ jobs.db

# Fix ownership (replace 'username' with your user)
sudo chown -R username:username uploads/ results/ jobs.db

# Fix permissions
chmod 755 uploads/ results/
chmod 644 jobs.db
```

#### Issue: Database Locked

```bash
# Find process using database
fuser jobs.db

# Or using lsof
lsof jobs.db

# Wait and retry, or if safe, kill the process
kill <PID>
```

#### Issue: Disk Space Not Freed

```bash
# Check actual disk usage
du -sh results/* | sort -h

# Check for deleted but open files
lsof +L1

# Force filesystem to release space
sync && echo 3 > /proc/sys/vm/drop_caches  # Requires root
```

#### Issue: Cleanup Takes Too Long

Optimize performance:

```bash
# Run with smaller batch size
python cleanup_jobs.py --batch-size 10

# Skip large directories temporarily
python cleanup_jobs.py --skip-large

# Increase logging to identify bottleneck
python cleanup_jobs.py --verbose --dry-run
```

### Getting Help

If you encounter issues:

1. **Check logs** for error messages:
   ```bash
   tail -100 cleanup_jobs.log | grep -i error
   ```

2. **Run in debug mode**:
   ```bash
   python cleanup_jobs.py --verbose --dry-run
   ```

3. **Verify installation**:
   ```bash
   python -c "import cleanup_jobs; print('Script OK')"
   ```

4. **Test database connection**:
   ```bash
   sqlite3 jobs.db ".tables"
   ```

## Best Practices

### Regular Maintenance

1. **Weekly Review**: Check cleanup summaries weekly
   ```bash
   # Review weekly summaries
   ls -lt cleanup_summary_*.json | head -7
   ```

2. **Monthly Analysis**: Analyze trends monthly
   ```bash
   # Monthly space freed
   grep "Total disk space freed" cleanup_jobs.log | \
     awk '{print substr($1,1,7), $7}' | \
     awk '{a[$1]+=$2} END {for(i in a) print i, a[i]/1024 " GB"}'
   ```

3. **Quarterly Tuning**: Adjust retention based on usage
   ```bash
   # Average job age at cleanup
   sqlite3 jobs.db "
   SELECT AVG(julianday(data_cleaned_at) - julianday(completed_at)) as avg_days
   FROM jobs WHERE data_cleaned_at IS NOT NULL;"
   ```

### Safety Measures

1. **Always test with dry-run** before changing retention:
   ```bash
   python cleanup_jobs.py --dry-run --success-retention-days 3
   ```

2. **Backup important results** before they expire:
   ```bash
   # Archive jobs older than 5 days
   tar -czf backup_$(date +%Y%m%d).tar.gz \
     $(find results -maxdepth 1 -type d -mtime +5)
   ```

3. **Monitor disk usage** proactively:
   ```bash
   # Set up disk usage alert
   USAGE=$(df /path/to/results | awk 'NR==2 {print $5}' | sed 's/%//')
   if [ $USAGE -gt 80 ]; then
     echo "Warning: Disk usage at ${USAGE}%" | mail -s "EEMT Disk Alert" admin@example.com
   fi
   ```

### Performance Tips

1. **Schedule during low-usage periods**: Run cleanup when system is idle

2. **Adjust batch size** for your system:
   ```bash
   # Smaller batches for limited resources
   export EEMT_CLEANUP_BATCH_SIZE=25
   
   # Larger batches for powerful systems
   export EEMT_CLEANUP_BATCH_SIZE=200
   ```

3. **Use nice** for background cleanup:
   ```bash
   nice -n 10 python cleanup_jobs.py
   ```

4. **Implement staged cleanup** for very large deployments:
   ```bash
   # Clean failed jobs first (usually smaller)
   python cleanup_jobs.py --success-retention-days 999 --failed-retention-hours 12
   
   # Then clean successful jobs
   python cleanup_jobs.py --success-retention-days 7 --failed-retention-hours 999
   ```

## Summary

The EEMT cleanup scripts provide flexible, automated management of job data to maintain optimal system performance. Key points:

- **Simple setup**: One command to enable automated cleanup
- **Configurable retention**: Adjust to your needs
- **Safe operation**: Dry-run mode and job config preservation
- **Multiple scheduling options**: Cron, systemd, or manual
- **Comprehensive logging**: Full visibility into cleanup operations

Regular use of these cleanup scripts ensures your EEMT deployment remains efficient and responsive even with high job volumes.