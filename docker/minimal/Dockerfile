FROM python:3.12-slim

LABEL description="EEMT Minimal Test Container for Web Interface Testing"
LABEL version="test"

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        git \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy web interface
COPY web-interface/ /app/

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.py

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create mock workflow scripts for testing
RUN mkdir -p /opt/eemt/bin/ && \
    echo '#!/usr/bin/env python3' > /opt/eemt/bin/run-solar-workflow.py && \
    echo 'import sys, time, random' >> /opt/eemt/bin/run-solar-workflow.py && \
    echo 'print("Mock solar workflow starting...")' >> /opt/eemt/bin/run-solar-workflow.py && \
    echo 'for i in range(10):' >> /opt/eemt/bin/run-solar-workflow.py && \
    echo '    print(f"Processing step {i+1}/10")' >> /opt/eemt/bin/run-solar-workflow.py && \
    echo '    time.sleep(2)' >> /opt/eemt/bin/run-solar-workflow.py && \
    echo 'print("workflow completed successfully")' >> /opt/eemt/bin/run-solar-workflow.py && \
    chmod +x /opt/eemt/bin/run-solar-workflow.py

# Create directories
RUN mkdir -p /app/{uploads,results,temp,cache,shared}

# Set environment
ENV PYTHONPATH="/app:/opt/eemt:$PYTHONPATH"
ENV PATH="/scripts:$PATH"

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/api/system/status || exit 1

# Default command
CMD ["python", "app.py"]