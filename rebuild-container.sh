#!/bin/bash
# Script to rebuild EEMT Docker container with latest code changes

echo "====================================="
echo "EEMT Container Rebuild Script"
echo "====================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Stopping any running EEMT containers...${NC}"
docker ps -q --filter "ancestor=eemt:ubuntu24.04" | xargs -r docker stop
docker ps -q --filter "ancestor=eemt-web" | xargs -r docker stop

echo -e "${YELLOW}Step 2: Removing old containers...${NC}"
docker ps -aq --filter "ancestor=eemt:ubuntu24.04" | xargs -r docker rm
docker ps -aq --filter "ancestor=eemt-web" | xargs -r docker rm

echo -e "${YELLOW}Step 3: Building base EEMT container...${NC}"
cd docker/ubuntu/24.04/
./build.sh
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to build base container${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 4: Building web interface container...${NC}"
cd ../../../
docker build -t eemt-web -f docker/web-interface/Dockerfile .
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to build web interface container${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 5: Verifying container builds...${NC}"
if docker images | grep -q "eemt.*ubuntu24.04"; then
    echo -e "${GREEN}✓ Base container built successfully${NC}"
else
    echo -e "${RED}✗ Base container not found${NC}"
    exit 1
fi

if docker images | grep -q "eemt-web"; then
    echo -e "${GREEN}✓ Web interface container built successfully${NC}"
else
    echo -e "${RED}✗ Web interface container not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 6: Testing container functionality...${NC}"
# Test base container
docker run --rm eemt:ubuntu24.04 python --version
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Python is working in base container${NC}"
else
    echo -e "${RED}✗ Python test failed${NC}"
fi

# Test GRASS GIS
docker run --rm eemt:ubuntu24.04 grass --version
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ GRASS GIS is working in base container${NC}"
else
    echo -e "${RED}✗ GRASS GIS test failed${NC}"
fi

# Test workflow script
docker run --rm eemt:ubuntu24.04 python /opt/eemt/bin/run-solar-workflow.py --help
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Solar workflow script is accessible${NC}"
else
    echo -e "${RED}✗ Solar workflow script test failed${NC}"
fi

echo ""
echo -e "${GREEN}====================================="
echo "Container rebuild complete!"
echo "=====================================${NC}"
echo ""
echo "To start the web interface, run:"
echo "  docker-compose up"
echo ""
echo "Or manually:"
echo "  docker run -p 5000:5000 -v \$(pwd)/data:/app/data eemt-web"