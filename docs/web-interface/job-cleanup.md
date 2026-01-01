# Job Data Cleanup System

The EEMT web interface includes an automated job data cleanup system to manage disk space by removing old job data while preserving job metadata for auditing and analysis.

## Overview

The cleanup system automatically manages job data retention with configurable policies:

- **Successful Jobs**: Output data deleted after 7 days, job configurations preserved indefinitely
- **Failed Jobs**: All data deleted after 12 hours to free resources quickly
- **Job Metadata**: Always preserved in the database for historical analysis
- **Configurable Retention**: Adjust periods via environment variables
- **Manual Cleanup**: API endpoint and CLI script for on-demand cleanup

!!! info "Data Retention Philosophy"
    The cleanup system balances disk space management with data preservation needs:
    
    - Job configurations and metadata are always retained for analysis
    - Output data for successful jobs is kept long enough for users to download
    - Failed job data is cleaned quickly as it's typically not needed
    - All retention periods are configurable to match your requirements

## Architecture

```mermaid
graph TB
    subgraph "Cleanup Components"
        CS[cleanup_jobs.py<br/>Standalone Script]
        API[/api/cleanup<br/>REST Endpoint]
        CRON[Cron Job<br/>Automated Schedule]
        SD[Systemd Timer<br/>Alternative Scheduler]
    end
    
    subgraph "Data Storage"
        DB[(SQLite<br/>Job Database)]
        UP[uploads/<br/>Input DEMs]
        RES[results/<br/>Output Data]
        TEMP[temp/<br/>Working Files]
    end
    
    subgraph "Cleanup Process"
        SCAN[Scan Jobs]
        CHECK[Check Age]
        DEL[Delete Data]
        LOG[Update Logs]
    end
    
    CS --> SCAN
    API --> SCAN
    CRON --> CS
    SD --> CS
    
    SCAN --> CHECK
    CHECK --> DEL
    DEL --> LOG
    
    DEL --> UP
    DEL --> RES
    DEL --> TEMP
    LOG --> DB
```

## Retention Policies

### Default Policies

| Job Status | Data Type | Retention Period | Action |
|------------|-----------|------------------|--------|
| **Successful** | Output data | 7 days | Delete files, keep DB record |
| **Successful** | Input DEM | 7 days | Delete file if exists |
| **Successful** | Job metadata | Forever | Preserved in database |
| **Failed** | All data | 12 hours | Delete all files |
| **Failed** | Job metadata | Forever | Preserved with error info |
| **Running** | All data | N/A | Never deleted automatically |
| **Pending** | All data | N/A | Never deleted automatically |

### Configurable Retention

Adjust retention periods using environment variables:

```bash
# Set retention periods (in hours)
export EEMT_SUCCESS_RETENTION_HOURS=168  # 7 days (default)
export EEMT_FAILED_RETENTION_HOURS=12    # 12 hours (default)

# Examples of common configurations
export EEMT_SUCCESS_RETENTION_HOURS=336  # 14 days for longer retention
export EEMT_SUCCESS_RETENTION_HOURS=72   # 3 days for rapid cleanup
export EEMT_FAILED_RETENTION_HOURS=24    # 24 hours for debugging
```

## Cleanup Script Usage

### Standalone Script (`cleanup_jobs.py`)

The cleanup script can be run manually or scheduled:

#### Basic Usage

```bash
# Run cleanup with default settings
python scripts/cleanup_jobs.py

# Specify custom database and directories
python scripts/cleanup_jobs.py \
    --db-path /path/to/jobs.db \
    --uploads-dir /path/to/uploads \
    --results-dir /path/to/results
```

#### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--db-path` | Path to SQLite database | `./jobs.db` |
| `--uploads-dir` | Directory containing uploaded DEMs | `./uploads` |
| `--results-dir` | Directory containing job outputs | `./results` |
| `--success-retention` | Hours to keep successful job data | 168 (7 days) |
| `--failed-retention` | Hours to keep failed job data | 12 |
| `--dry-run` | Preview cleanup without deleting | False |
| `--verbose` | Enable detailed logging | False |

#### Dry Run Mode

Preview what would be deleted without making changes:

```bash
# See what would be cleaned up
python scripts/cleanup_jobs.py --dry-run --verbose

# Example output
[DRY RUN] Would clean job job-20240115-123456 (status: completed, age: 8.2 days)
[DRY RUN] Would delete: uploads/job-20240115-123456_dem.tif
[DRY RUN] Would delete: results/job-20240115-123456/ (15 GB)
[DRY RUN] Summary: Would clean 3 jobs, freeing ~45 GB
```

#### Verbose Output

Get detailed information during cleanup:

```bash
python scripts/cleanup_jobs.py --verbose

# Example output
[INFO] Starting job cleanup process...
[INFO] Checking job job-20240115-123456 (completed, 8 days old)
[INFO] Deleting uploads/job-20240115-123456_dem.tif (250 MB)
[INFO] Deleting results/job-20240115-123456/ (15 GB)
[INFO] Updated database: marked job as cleaned
[INFO] Cleaned 3 successful jobs (freed 45 GB)
[INFO] Cleaned 2 failed jobs (freed 500 MB)
[INFO] Cleanup completed successfully
```

## Automated Scheduling

### Cron Setup

Use the provided setup script for automatic cron configuration:

```bash
# Install cron job (runs daily at 2 AM)
./scripts/setup_cleanup_cron.sh install

# Verify installation
./scripts/setup_cleanup_cron.sh status

# Remove cron job
./scripts/setup_cleanup_cron.sh remove
```

#### Manual Cron Configuration

For custom scheduling, edit crontab directly:

```bash
# Edit crontab
crontab -e

# Add cleanup job (adjust schedule as needed)
# Daily at 2:00 AM
0 2 * * * cd /path/to/eemt/web-interface && /usr/bin/python3 scripts/cleanup_jobs.py >> logs/cleanup.log 2>&1

# Every 6 hours
0 */6 * * * cd /path/to/eemt/web-interface && /usr/bin/python3 scripts/cleanup_jobs.py

# Weekly on Sunday at 3 AM
0 3 * * 0 cd /path/to/eemt/web-interface && /usr/bin/python3 scripts/cleanup_jobs.py
```

### Systemd Timer Setup

For systems using systemd, use timer units for more control:

```bash
# Install systemd timer and service
./scripts/setup_cleanup_cron.sh install-systemd

# Check timer status
systemctl --user status eemt-cleanup.timer

# View cleanup logs
journalctl --user -u eemt-cleanup.service

# Manual trigger
systemctl --user start eemt-cleanup.service
```

#### Systemd Configuration Files

The setup script creates these systemd files:

**`~/.config/systemd/user/eemt-cleanup.service`**:
```ini
[Unit]
Description=EEMT Job Cleanup Service
After=network.target

[Service]
Type=oneshot
WorkingDirectory=/path/to/eemt/web-interface
ExecStart=/usr/bin/python3 scripts/cleanup_jobs.py
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**`~/.config/systemd/user/eemt-cleanup.timer`**:
```ini
[Unit]
Description=Daily EEMT Job Cleanup Timer
Requires=eemt-cleanup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

## Docker Integration

### Docker Compose Configuration

The cleanup system integrates with Docker deployments:

```yaml
# docker-compose.yml
services:
  eemt-web:
    image: eemt-web:latest
    environment:
      - EEMT_SUCCESS_RETENTION_HOURS=168
      - EEMT_FAILED_RETENTION_HOURS=12
      - EEMT_ENABLE_AUTO_CLEANUP=true
      - EEMT_CLEANUP_SCHEDULE="0 2 * * *"  # Cron expression
    volumes:
      - ./data/uploads:/app/uploads
      - ./data/results:/app/results
      - ./jobs.db:/app/jobs.db
```

### Container Cleanup Script

Run cleanup inside the web interface container:

```bash
# Execute cleanup in running container
docker exec eemt-web python scripts/cleanup_jobs.py

# Run cleanup in new container
docker run --rm \
  -v $(pwd)/uploads:/app/uploads \
  -v $(pwd)/results:/app/results \
  -v $(pwd)/jobs.db:/app/jobs.db \
  eemt-web python scripts/cleanup_jobs.py
```

### Kubernetes CronJob

For Kubernetes deployments, use a CronJob resource:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: eemt-cleanup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: eemt-web:latest
            command:
            - python
            - scripts/cleanup_jobs.py
            env:
            - name: EEMT_SUCCESS_RETENTION_HOURS
              value: "168"
            - name: EEMT_FAILED_RETENTION_HOURS
              value: "12"
            volumeMounts:
            - name: data
              mountPath: /app/data
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: eemt-data-pvc
          restartPolicy: OnFailure
```

## API Endpoint

### REST API for Manual Cleanup

Trigger cleanup via the web interface API:

#### Endpoint Details

```http
POST /api/cleanup
Content-Type: application/json

{
  "dry_run": false,
  "success_retention_hours": 168,
  "failed_retention_hours": 12
}
```

#### Response Format

```json
{
  "success": true,
  "cleaned_jobs": {
    "successful": 3,
    "failed": 2
  },
  "space_freed": {
    "bytes": 48318382080,
    "human_readable": "45.0 GB"
  },
  "details": [
    {
      "job_id": "job-20240115-123456",
      "status": "completed",
      "age_days": 8.2,
      "space_freed": "15.0 GB"
    }
  ]
}
```

#### Usage Examples

```bash
# Trigger cleanup with defaults
curl -X POST http://localhost:5000/api/cleanup

# Dry run to preview
curl -X POST http://localhost:5000/api/cleanup \
  -H "Content-Type: application/json" \
  -d '{"dry_run": true}'

# Custom retention periods
curl -X POST http://localhost:5000/api/cleanup \
  -H "Content-Type: application/json" \
  -d '{
    "success_retention_hours": 72,
    "failed_retention_hours": 6
  }'
```

### Python Client Example

```python
import requests
from datetime import datetime, timedelta

def cleanup_old_jobs(base_url="http://localhost:5000", dry_run=True):
    """Trigger job cleanup via API"""
    
    response = requests.post(
        f"{base_url}/api/cleanup",
        json={
            "dry_run": dry_run,
            "success_retention_hours": 168,  # 7 days
            "failed_retention_hours": 12     # 12 hours
        }
    )
    
    if response.status_code == 200:
        result = response.json()
        print(f"Cleanup {'preview' if dry_run else 'completed'}:")
        print(f"  Successful jobs cleaned: {result['cleaned_jobs']['successful']}")
        print(f"  Failed jobs cleaned: {result['cleaned_jobs']['failed']}")
        print(f"  Space freed: {result['space_freed']['human_readable']}")
    else:
        print(f"Cleanup failed: {response.text}")

# Preview cleanup
cleanup_old_jobs(dry_run=True)

# Execute cleanup
cleanup_old_jobs(dry_run=False)
```

## Configuration Options

### Environment Variables

Configure cleanup behavior through environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `EEMT_SUCCESS_RETENTION_HOURS` | Hours to keep successful job data | 168 (7 days) |
| `EEMT_FAILED_RETENTION_HOURS` | Hours to keep failed job data | 12 |
| `EEMT_ENABLE_AUTO_CLEANUP` | Enable automatic cleanup on schedule | false |
| `EEMT_CLEANUP_SCHEDULE` | Cron expression for auto cleanup | "0 2 * * *" |
| `EEMT_CLEANUP_LOG_LEVEL` | Logging verbosity (DEBUG, INFO, WARNING, ERROR) | INFO |
| `EEMT_CLEANUP_BATCH_SIZE` | Number of jobs to process per batch | 100 |
| `EEMT_CLEANUP_DRY_RUN` | Always run in dry-run mode | false |

### Configuration File

Create a configuration file for complex setups:

**`cleanup_config.yaml`**:
```yaml
# Retention policies
retention:
  successful_jobs:
    hours: 168  # 7 days
    keep_metadata: true
    keep_logs: false
  failed_jobs:
    hours: 12
    keep_metadata: true
    keep_error_logs: true

# Cleanup schedule
schedule:
  enabled: true
  cron: "0 2 * * *"  # Daily at 2 AM
  
# Directories
paths:
  database: ./jobs.db
  uploads: ./uploads
  results: ./results
  logs: ./logs

# Performance
performance:
  batch_size: 100
  parallel_delete: true
  max_workers: 4

# Notifications (optional)
notifications:
  email:
    enabled: false
    smtp_server: smtp.gmail.com
    recipients:
      - admin@example.com
  slack:
    enabled: false
    webhook_url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

Load configuration in cleanup script:

```python
import yaml

with open('cleanup_config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Use configuration
success_retention = config['retention']['successful_jobs']['hours']
failed_retention = config['retention']['failed_jobs']['hours']
```

## Monitoring and Logging

### Log Files

Cleanup operations are logged to multiple locations:

1. **Application Logs**: `logs/cleanup.log`
2. **System Logs**: `/var/log/syslog` (when using cron)
3. **Journal**: `journalctl` (when using systemd)
4. **Container Logs**: `docker logs eemt-web`

### Log Format

```
2024-01-20 02:00:01 INFO: Starting job cleanup process
2024-01-20 02:00:02 INFO: Found 45 jobs to check
2024-01-20 02:00:03 INFO: Cleaning job job-20240113-123456 (completed, 7.5 days old)
2024-01-20 02:00:05 INFO: Deleted uploads/job-20240113-123456_dem.tif (250 MB)
2024-01-20 02:00:08 INFO: Deleted results/job-20240113-123456/ (15 GB)
2024-01-20 02:00:09 INFO: Cleanup summary: 3 successful, 2 failed, 45.5 GB freed
2024-01-20 02:00:09 INFO: Cleanup completed successfully
```

### Monitoring Metrics

Track cleanup effectiveness with these metrics:

```python
# Example monitoring script
import sqlite3
from datetime import datetime, timedelta

def get_cleanup_metrics(db_path="jobs.db"):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Jobs cleaned in last 24 hours
    yesterday = datetime.now() - timedelta(hours=24)
    cursor.execute("""
        SELECT COUNT(*), SUM(data_size_mb) 
        FROM jobs 
        WHERE data_cleaned_at > ?
    """, (yesterday.isoformat(),))
    
    count, size_mb = cursor.fetchone()
    
    # Disk space usage
    cursor.execute("""
        SELECT 
            status,
            COUNT(*) as count,
            SUM(data_size_mb) as total_mb
        FROM jobs
        WHERE data_cleaned_at IS NULL
        GROUP BY status
    """)
    
    usage_by_status = cursor.fetchall()
    
    print(f"Cleanup Metrics (Last 24h):")
    print(f"  Jobs cleaned: {count or 0}")
    print(f"  Space freed: {(size_mb or 0) / 1024:.1f} GB")
    print(f"\nCurrent Usage:")
    for status, count, mb in usage_by_status:
        print(f"  {status}: {count} jobs, {mb/1024:.1f} GB")
    
    conn.close()

# Run metrics check
get_cleanup_metrics()
```

## Troubleshooting

### Common Issues

#### 1. Cleanup Not Running Automatically

**Check cron job:**
```bash
# List cron jobs
crontab -l

# Check cron service
systemctl status cron

# View cron logs
grep CRON /var/log/syslog
```

**Check systemd timer:**
```bash
# Timer status
systemctl --user status eemt-cleanup.timer

# List all timers
systemctl --user list-timers

# View service logs
journalctl --user -u eemt-cleanup.service -n 50
```

#### 2. Permission Denied Errors

```bash
# Check file permissions
ls -la uploads/ results/

# Fix ownership
sudo chown -R $(whoami):$(whoami) uploads/ results/

# Fix permissions
chmod -R 755 uploads/ results/
```

#### 3. Database Locked Error

```bash
# Check for running processes
fuser jobs.db

# Kill blocking process if needed
kill -9 <PID>

# Verify database integrity
sqlite3 jobs.db "PRAGMA integrity_check;"
```

#### 4. Disk Space Not Being Freed

```bash
# Check if files are actually deleted
du -sh uploads/ results/

# Check for open file handles
lsof | grep results

# Force filesystem sync
sync

# Check available space
df -h .
```

#### 5. Cleanup Taking Too Long

Optimize cleanup performance:

```python
# Use parallel deletion
python scripts/cleanup_jobs.py --parallel --workers 4

# Process in smaller batches
python scripts/cleanup_jobs.py --batch-size 50

# Skip large directories first
python scripts/cleanup_jobs.py --skip-large --size-threshold 10G
```

### Debug Mode

Enable detailed debugging output:

```bash
# Set debug environment variable
export EEMT_CLEANUP_LOG_LEVEL=DEBUG

# Run with maximum verbosity
python scripts/cleanup_jobs.py --verbose --debug

# Debug output includes:
# - SQL queries executed
# - File operations attempted
# - Time taken for each operation
# - Memory usage statistics
```

### Recovery Procedures

#### Restore Accidentally Deleted Data

If important data was deleted by cleanup:

1. **Check backups** (if configured):
   ```bash
   # Restore from backup
   rsync -av /backup/eemt/results/job-id/ ./results/job-id/
   ```

2. **Recover from database**:
   ```sql
   -- Job metadata is preserved
   SELECT * FROM jobs WHERE job_id = 'job-20240120-123456';
   ```

3. **Re-run job** if necessary:
   ```bash
   # Use preserved configuration
   python scripts/rerun_job.py --job-id job-20240120-123456
   ```

#### Reset Cleanup State

Clear cleanup history and start fresh:

```sql
-- Reset cleanup timestamps
UPDATE jobs SET data_cleaned_at = NULL WHERE data_cleaned_at IS NOT NULL;

-- Clear cleanup log entries
DELETE FROM cleanup_log;

-- Vacuum database
VACUUM;
```

## Best Practices

### 1. Regular Monitoring

Set up monitoring alerts:

```bash
# Daily check script
#!/bin/bash
SPACE_USED=$(du -sb results/ | cut -f1)
MAX_SPACE=107374182400  # 100 GB

if [ $SPACE_USED -gt $MAX_SPACE ]; then
    echo "Warning: Results directory using $(($SPACE_USED / 1073741824)) GB" | \
        mail -s "EEMT Cleanup Alert" admin@example.com
fi
```

### 2. Backup Important Results

Before cleanup, backup critical data:

```bash
# Backup successful jobs before cleanup
rsync -av --include="*completed*" results/ /backup/eemt/results/

# Archive old successful jobs
tar -czf archived_jobs_$(date +%Y%m).tar.gz \
    $(find results/ -name "*completed*" -mtime +7)
```

### 3. Gradual Cleanup

Implement staged cleanup for safety:

```python
# Two-stage cleanup process
def staged_cleanup():
    # Stage 1: Mark for deletion
    mark_jobs_for_cleanup(age_days=7)
    
    # Stage 2: Delete marked jobs (24h later)
    delete_marked_jobs(marked_before=24)
```

### 4. Audit Trail

Maintain cleanup audit logs:

```sql
-- Create audit table
CREATE TABLE cleanup_audit (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    job_id TEXT,
    action TEXT,
    space_freed_mb INTEGER,
    user TEXT
);

-- Log cleanup actions
INSERT INTO cleanup_audit (job_id, action, space_freed_mb, user)
VALUES ('job-123', 'deleted_results', 15360, 'auto_cleanup');
```

### 5. Capacity Planning

Monitor growth trends:

```python
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

def plot_storage_trends():
    # Get historical data
    dates, usage = get_storage_history()
    
    # Plot trend
    plt.figure(figsize=(10, 6))
    plt.plot(dates, usage)
    plt.xlabel('Date')
    plt.ylabel('Storage (GB)')
    plt.title('EEMT Storage Usage Trend')
    plt.grid(True)
    plt.savefig('storage_trend.png')
```

## Integration Examples

### Slack Notifications

Send cleanup summaries to Slack:

```python
import requests
import json

def send_slack_notification(webhook_url, message):
    payload = {
        "text": f"EEMT Cleanup Report",
        "attachments": [{
            "color": "good",
            "fields": [
                {"title": "Jobs Cleaned", "value": message['jobs_cleaned'], "short": True},
                {"title": "Space Freed", "value": message['space_freed'], "short": True},
                {"title": "Status", "value": "Success", "short": True}
            ]
        }]
    }
    requests.post(webhook_url, json=payload)
```

### Email Reports

Send daily cleanup reports:

```python
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def send_cleanup_report(recipient, stats):
    msg = MIMEMultipart()
    msg['Subject'] = 'EEMT Daily Cleanup Report'
    msg['From'] = 'eemt@example.com'
    msg['To'] = recipient
    
    body = f"""
    Daily Cleanup Report
    ====================
    
    Jobs Cleaned: {stats['jobs_cleaned']}
    Space Freed: {stats['space_freed']}
    
    Current Storage Usage: {stats['current_usage']}
    Available Space: {stats['available_space']}
    
    Next cleanup scheduled for: {stats['next_run']}
    """
    
    msg.attach(MIMEText(body, 'plain'))
    
    with smtplib.SMTP('localhost') as server:
        server.send_message(msg)
```

### Prometheus Metrics

Export cleanup metrics for monitoring:

```python
from prometheus_client import Counter, Gauge, Histogram

# Define metrics
cleanup_runs = Counter('eemt_cleanup_runs_total', 'Total cleanup runs')
jobs_cleaned = Counter('eemt_jobs_cleaned_total', 'Total jobs cleaned', ['status'])
space_freed = Counter('eemt_space_freed_bytes_total', 'Total space freed')
cleanup_duration = Histogram('eemt_cleanup_duration_seconds', 'Cleanup duration')
current_usage = Gauge('eemt_storage_usage_bytes', 'Current storage usage')

# Update metrics during cleanup
@cleanup_duration.time()
def run_cleanup():
    cleanup_runs.inc()
    # ... cleanup logic ...
    jobs_cleaned.labels(status='completed').inc(3)
    space_freed.inc(45 * 1024 * 1024 * 1024)  # 45 GB
    current_usage.set(get_current_usage())
```

## Security Considerations

### Access Control

Restrict cleanup operations:

```python
from functools import wraps
from flask import request, abort

def require_admin(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth = request.headers.get('Authorization')
        if not verify_admin_token(auth):
            abort(403)
        return f(*args, **kwargs)
    return decorated_function

@app.route('/api/cleanup', methods=['POST'])
@require_admin
def api_cleanup():
    # Only admins can trigger cleanup
    return run_cleanup()
```

### Audit Logging

Track all cleanup operations:

```python
import logging
import json
from datetime import datetime

class AuditLogger:
    def __init__(self, log_file='cleanup_audit.log'):
        self.logger = logging.getLogger('cleanup_audit')
        handler = logging.FileHandler(log_file)
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def log_cleanup(self, user, action, details):
        audit_entry = {
            'timestamp': datetime.now().isoformat(),
            'user': user,
            'action': action,
            'details': details,
            'ip_address': request.remote_addr
        }
        self.logger.info(json.dumps(audit_entry))
```

### Safe Deletion

Implement safeguards against accidental deletion:

```python
def safe_delete(path, job_id):
    """Safely delete files with verification"""
    
    # Verify path is within allowed directories
    allowed_dirs = ['/app/uploads', '/app/results']
    if not any(str(path).startswith(d) for d in allowed_dirs):
        raise ValueError(f"Attempted to delete outside allowed directories: {path}")
    
    # Verify job ownership
    if not verify_job_ownership(job_id, path):
        raise ValueError(f"Path does not belong to job {job_id}")
    
    # Create backup before deletion (optional)
    if ENABLE_CLEANUP_BACKUP:
        backup_path = f"/backup/{job_id}/{path.name}"
        shutil.copy2(path, backup_path)
    
    # Perform deletion
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    
    return True
```

## Summary

The EEMT job cleanup system provides flexible, automated management of job data to maintain optimal disk usage while preserving important metadata and configurations. Key features include:

- **Configurable retention policies** for different job states
- **Multiple scheduling options** (cron, systemd, manual)
- **Docker and Kubernetes integration** for containerized deployments
- **Comprehensive logging and monitoring** capabilities
- **Safety features** including dry-run mode and audit trails
- **REST API** for programmatic control

The system ensures that your EEMT deployment remains performant and manageable even with high job volumes, while maintaining data integrity and providing recovery options when needed.