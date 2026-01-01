#!/bin/bash
#
# EEMT Job Cleanup - Cron Setup Script
#
# This script sets up automated job cleanup using cron or systemd timer.
# Supports both user and system-wide installation.
#
# Usage:
#     ./setup_cleanup_cron.sh [--system|--user] [--method cron|systemd]
#
# Options:
#     --system    Install system-wide (requires sudo)
#     --user      Install for current user only (default)
#     --method    Use 'cron' or 'systemd' for scheduling (default: cron)
#

set -euo pipefail

# Script directory (where cleanup script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/cleanup_jobs.py"

# Default configuration
INSTALL_TYPE="user"
SCHEDULE_METHOD="cron"
CLEANUP_INTERVAL="0 2 * * *"  # Daily at 2 AM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --system)
            INSTALL_TYPE="system"
            shift
            ;;
        --user)
            INSTALL_TYPE="user"
            shift
            ;;
        --method)
            SCHEDULE_METHOD="$2"
            shift 2
            ;;
        --help|-h)
            echo "EEMT Job Cleanup - Cron Setup Script"
            echo ""
            echo "Usage: $0 [--system|--user] [--method cron|systemd]"
            echo ""
            echo "Options:"
            echo "  --system    Install system-wide (requires sudo)"
            echo "  --user      Install for current user only (default)"
            echo "  --method    Use 'cron' or 'systemd' for scheduling (default: cron)"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Validate cleanup script exists
if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
    echo "Error: Cleanup script not found at $CLEANUP_SCRIPT" >&2
    exit 1
fi

# Make cleanup script executable
chmod +x "$CLEANUP_SCRIPT"

echo "EEMT Job Cleanup Setup"
echo "======================"
echo "Script location: $CLEANUP_SCRIPT"
echo "Install type: $INSTALL_TYPE"
echo "Schedule method: $SCHEDULE_METHOD"
echo ""

# Function to setup cron job
setup_cron() {
    local cron_entry="$CLEANUP_INTERVAL cd $SCRIPT_DIR && python3 cleanup_jobs.py >> cleanup_jobs.log 2>&1"
    
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        # System-wide cron job
        local cron_file="/etc/cron.d/eemt-cleanup"
        echo "Setting up system-wide cron job..."
        
        if [[ $EUID -ne 0 ]]; then
            echo "Error: System installation requires sudo privileges" >&2
            exit 1
        fi
        
        cat > "$cron_file" << EOF
# EEMT Job Data Cleanup
# Runs daily at 2 AM to clean up old job data
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$CLEANUP_INTERVAL root cd $SCRIPT_DIR && python3 cleanup_jobs.py >> cleanup_jobs.log 2>&1
EOF
        
        chmod 644 "$cron_file"
        echo "Created system cron job: $cron_file"
        
    else
        # User cron job
        echo "Setting up user cron job..."
        
        # Add to user's crontab
        (crontab -l 2>/dev/null | grep -v "EEMT.*cleanup_jobs.py" || true; echo "# EEMT Job Data Cleanup"; echo "$cron_entry") | crontab -
        
        echo "Added user cron job:"
        echo "  $cron_entry"
    fi
}

# Function to setup systemd timer
setup_systemd() {
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        local service_file="/etc/systemd/system/eemt-cleanup.service"
        local timer_file="/etc/systemd/system/eemt-cleanup.timer"
        
        echo "Setting up system systemd timer..."
        
        if [[ $EUID -ne 0 ]]; then
            echo "Error: System installation requires sudo privileges" >&2
            exit 1
        fi
        
    else
        local service_file="$HOME/.config/systemd/user/eemt-cleanup.service"
        local timer_file="$HOME/.config/systemd/user/eemt-cleanup.timer"
        
        echo "Setting up user systemd timer..."
        
        # Create user systemd directory if it doesn't exist
        mkdir -p "$(dirname "$service_file")"
    fi
    
    # Create service file
    cat > "$service_file" << EOF
[Unit]
Description=EEMT Job Data Cleanup Service
Documentation=file://$CLEANUP_SCRIPT

[Service]
Type=oneshot
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/python3 $CLEANUP_SCRIPT
User=$(whoami)
Group=$(id -gn)
StandardOutput=append:$SCRIPT_DIR/cleanup_jobs.log
StandardError=append:$SCRIPT_DIR/cleanup_jobs.log

[Install]
WantedBy=default.target
EOF
    
    # Create timer file
    cat > "$timer_file" << EOF
[Unit]
Description=EEMT Job Data Cleanup Timer
Documentation=file://$CLEANUP_SCRIPT

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF
    
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        chmod 644 "$service_file" "$timer_file"
        systemctl daemon-reload
        systemctl enable eemt-cleanup.timer
        systemctl start eemt-cleanup.timer
        
        echo "Created system systemd timer:"
        echo "  Service: $service_file"
        echo "  Timer: $timer_file"
        echo "  Status: $(systemctl is-active eemt-cleanup.timer)"
        
    else
        chmod 644 "$service_file" "$timer_file"
        systemctl --user daemon-reload
        systemctl --user enable eemt-cleanup.timer
        systemctl --user start eemt-cleanup.timer
        
        echo "Created user systemd timer:"
        echo "  Service: $service_file"
        echo "  Timer: $timer_file"
        echo "  Status: $(systemctl --user is-active eemt-cleanup.timer)"
    fi
}

# Main setup logic
case "$SCHEDULE_METHOD" in
    cron)
        setup_cron
        echo ""
        echo "Cron job setup complete!"
        if [[ "$INSTALL_TYPE" == "user" ]]; then
            echo "View current cron jobs with: crontab -l"
            echo "Remove cron job with: crontab -e (then delete the EEMT cleanup line)"
        else
            echo "View system cron job at: /etc/cron.d/eemt-cleanup"
            echo "Remove cron job with: sudo rm /etc/cron.d/eemt-cleanup"
        fi
        ;;
    systemd)
        setup_systemd
        echo ""
        echo "Systemd timer setup complete!"
        if [[ "$INSTALL_TYPE" == "user" ]]; then
            echo "Check timer status: systemctl --user status eemt-cleanup.timer"
            echo "View logs: journalctl --user -u eemt-cleanup.service"
            echo "Disable timer: systemctl --user stop eemt-cleanup.timer && systemctl --user disable eemt-cleanup.timer"
        else
            echo "Check timer status: systemctl status eemt-cleanup.timer"
            echo "View logs: journalctl -u eemt-cleanup.service"
            echo "Disable timer: sudo systemctl stop eemt-cleanup.timer && sudo systemctl disable eemt-cleanup.timer"
        fi
        ;;
    *)
        echo "Error: Unsupported schedule method '$SCHEDULE_METHOD'" >&2
        echo "Supported methods: cron, systemd" >&2
        exit 1
        ;;
esac

echo ""
echo "Manual testing:"
echo "  Test cleanup (dry run): python3 $CLEANUP_SCRIPT --dry-run"
echo "  Run cleanup manually: python3 $CLEANUP_SCRIPT"
echo "  View cleanup logs: tail -f $SCRIPT_DIR/cleanup_jobs.log"

echo ""
echo "Configuration:"
echo "  Successful job data retention: 7 days (set EEMT_SUCCESS_RETENTION_DAYS to change)"
echo "  Failed job data retention: 12 hours (set EEMT_FAILED_RETENTION_HOURS to change)"
echo "  Cleanup runs daily at 2 AM"