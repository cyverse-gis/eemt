FROM python:3.12-slim

LABEL description="EEMT Documentation Server with MkDocs Material"
LABEL version="2.0"

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /docs

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir \
    mkdocs-material==9.4.8 \
    mkdocs-minify-plugin==0.7.1 \
    pymdown-extensions==10.3.1 \
    mkdocs-git-revision-date-localized-plugin==1.2.1

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000 || exit 1

# Default command
CMD ["mkdocs", "serve", "--dev-addr", "0.0.0.0:8000"]