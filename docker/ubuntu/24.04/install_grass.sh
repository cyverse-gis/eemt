#!/bin/bash
# GRASS GIS Installation Script for EEMT - Minimal Container Version
# Optimized for headless container deployment without GUI dependencies

set -e

echo "Installing GRASS GIS for EEMT (minimal headless version)..."

# Update package lists
apt-get update

# Install essential GRASS GIS packages without GUI dependencies
echo "Installing minimal GRASS GIS packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    grass-core \
    grass-dev \
    gdal-bin \
    proj-bin \
    python3-gdal \
    python3-scipy \
    python3-numpy

# Verify installation
echo "Verifying GRASS GIS installation..."
GRASS_CMD=$(which grass84 2>/dev/null || which grass 2>/dev/null || echo "")

if [[ -n "$GRASS_CMD" ]]; then
    echo "GRASS GIS installation successful!"
    echo "Found GRASS command: $GRASS_CMD"
    $GRASS_CMD --version
else
    echo "Error: GRASS GIS installation failed - no grass command found"
    exit 1
fi

# Set up environment variables for Python integration
echo "Setting up GRASS GIS environment..."

# Find GRASS installation directory
GISBASE=$($GRASS_CMD --config path 2>/dev/null || echo "/usr/lib/grass84")
echo "GRASS GIS base directory: $GISBASE"

# Create EEMT bin directory
mkdir -p /opt/eemt/bin

# Create environment setup script
cat > /opt/eemt/bin/setup-grass-env.sh << EOF
#!/bin/bash
# GRASS GIS Environment Setup for EEMT

export GISBASE="$GISBASE"
export PATH="\$GISBASE/bin:\$PATH"
export LD_LIBRARY_PATH="\$GISBASE/lib:\$LD_LIBRARY_PATH"
export PYTHONPATH="\$GISBASE/etc/python:\$PYTHONPATH"
export GRASS_PYTHON=python3

# For CCTools integration
export GRASS_BATCH_JOB=1
export GRASS_OVERWRITE=1

echo "GRASS GIS environment configured for EEMT"
echo "GISBASE: \$GISBASE"
echo "Use 'grass84' command to start GRASS GIS"
EOF

chmod +x /opt/eemt/bin/setup-grass-env.sh

# Clean up
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

echo ""
echo "✅ GRASS GIS installation complete!"
echo "📍 Installation: $(which grass84)"
echo "🐍 Python module: Available via python3-grass package"
echo "⚙️  Environment: Source /opt/eemt/bin/setup-grass-env.sh"
echo ""
echo "Test with: grass84 --version"