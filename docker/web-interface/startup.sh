#!/bin/bash
#
# EEMT Web Interface Container Startup Script
# 
# This script handles container initialization including:
# - Optional cleanup cron job setup
# - Health check endpoints
# - Application startup
#

set -euo pipefail

echo "Starting EEMT Web Interface container..."

# Function to setup cleanup if enabled
setup_cleanup() {
    if [[ "${EEMT_CLEANUP_ENABLED:-true}" == "true" ]]; then
        echo "Setting up automated job data cleanup..."
        
        # Use environment variables for configuration
        local success_retention=${EEMT_SUCCESS_RETENTION_DAYS:-7}
        local failed_retention=${EEMT_FAILED_RETENTION_HOURS:-12}
        
        echo "Cleanup configuration:"
        echo "  - Successful job data retention: ${success_retention} days"
        echo "  - Failed job data retention: ${failed_retention} hours"
        echo "  - Schedule: Daily at 2 AM UTC"
        
        # Set up cron job for cleanup
        local cron_entry="0 2 * * * cd /app && python3 cleanup_jobs.py --success-retention-days ${success_retention} --failed-retention-hours ${failed_retention} >> /app/logs/cleanup.log 2>&1"
        
        # Add cron job (avoid duplicates)
        (crontab -l 2>/dev/null | grep -v "cleanup_jobs.py" || true; echo "# EEMT Job Data Cleanup"; echo "$cron_entry") | crontab -
        
        # Start cron service
        service cron start
        
        echo "Cleanup cron job configured successfully"
        
        # Run initial cleanup check (dry run)
        echo "Running initial cleanup check..."
        python3 /app/cleanup_jobs.py --dry-run > /app/logs/initial_cleanup_check.log 2>&1 || echo "Initial cleanup check completed with warnings"
        
    else
        echo "Automated cleanup is disabled (EEMT_CLEANUP_ENABLED=false)"
    fi
}

# Function to setup logging directory
setup_logging() {
    echo "Setting up logging..."
    mkdir -p /app/logs
    touch /app/logs/app.log
    touch /app/logs/cleanup.log
    echo "Logging configured"
}

# Function to wait for dependencies
wait_for_dependencies() {
    echo "Checking dependencies..."
    
    # Check if Docker socket is available (for local mode)
    if [[ -S /var/run/docker.sock ]]; then
        echo "Docker socket available - local container mode enabled"
    else
        echo "Docker socket not available - distributed mode or limited functionality"
    fi
    
    # Check Python environment
    python3 -c "import fastapi, sqlite3, pathlib; print('Python dependencies OK')" || {
        echo "ERROR: Python dependencies missing"
        exit 1
    }
    
    echo "Dependencies check complete"
}

# Function to run health check
health_check() {
    echo "Performing health check..."
    
    # Check if app.py can be imported
    python3 -c "import app; print('FastAPI app imports successfully')" || {
        echo "ERROR: FastAPI application import failed"
        return 1
    }
    
    echo "Health check passed"
}

# Main startup sequence
main() {
    echo "EEMT Web Interface Container Startup"
    echo "===================================="
    echo "Container mode: ${EEMT_MODE:-local}"
    echo "Host: ${EEMT_HOST:-0.0.0.0}"
    echo "Port: ${EEMT_PORT:-5000}"
    echo "Cleanup enabled: ${EEMT_CLEANUP_ENABLED:-true}"
    echo ""
    
    # Setup sequence
    setup_logging
    wait_for_dependencies
    health_check
    setup_cleanup
    
    echo ""
    echo "Container initialization complete!"
    echo "Starting FastAPI application..."
    echo ""
    
    # Start the main application
    if [[ "${EEMT_MODE:-local}" == "master" ]]; then
        echo "Starting in master mode with distributed workflow management..."
        # In master mode, we need to start both the web interface and Work Queue master
        exec python3 app.py
    else
        echo "Starting in local mode..."
        exec python3 app.py
    fi
}

# Handle cleanup on container shutdown
cleanup_on_exit() {
    echo "Container shutting down..."
    echo "$(date): Container shutdown" >> /app/logs/app.log
    
    # Stop cron if running
    service cron stop 2>/dev/null || true
    
    echo "Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT INT TERM

# Run main function
main "$@"