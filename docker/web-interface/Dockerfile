# Use test image as base for now
FROM eemt-test:minimal

LABEL authors="EEMT Development Team"
LABEL maintainer="tswetnam@cyverse.org"
LABEL description="EEMT Web Interface with distributed workflow management"
LABEL version="2.0"

# Install Docker CLI for container management and cron for cleanup tasks
RUN apt-get update && apt-get install -y \
    docker.io \
    curl \
    cron \
    systemd \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy web interface code
COPY web-interface/ /app/

# Copy container startup script
COPY docker/web-interface/startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Copy scripts for master/worker deployment
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.py

# Install Python dependencies for web interface
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /app/uploads /app/results /app/temp /app/cache /app/shared /app/logs

# Make cleanup scripts executable and set up permissions
RUN chmod +x /app/cleanup_jobs.py /app/setup_cleanup_cron.sh

# Create cron log file and set permissions
RUN touch /var/log/cron.log && chmod 666 /var/log/cron.log

# Set environment variables for cleanup
ENV PYTHONPATH="/app:/opt/eemt:$PYTHONPATH"
ENV PATH="/scripts:$PATH"
ENV EEMT_SUCCESS_RETENTION_DAYS=7
ENV EEMT_FAILED_RETENTION_HOURS=12
ENV EEMT_CLEANUP_ENABLED=true

# Expose ports
EXPOSE 5000 9123

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

# Default command - use startup script
CMD ["/app/startup.sh"]