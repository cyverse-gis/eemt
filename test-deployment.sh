#!/bin/bash
# EEMT Test Deployment Script
# Tests the complete Docker deployment with sample data

set -e

echo "🚀 EEMT Test Deployment Starting..."
echo "=================================="

# Configuration
SAMPLE_DEM="sol/examples/mcn_10m.tif"
WEB_PORT=5000
WORK_QUEUE_PORT=9123

# Step 1: Verify prerequisites
echo "📋 Step 1: Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker daemon not running. Please start Docker service."
    exit 1
fi

echo "✅ Docker is available"

# Step 2: Check sample data
echo "📋 Step 2: Verifying sample dataset..."

if [ ! -f "$SAMPLE_DEM" ]; then
    echo "❌ Sample DEM not found: $SAMPLE_DEM"
    exit 1
fi

echo "✅ Sample DEM found: $SAMPLE_DEM ($(du -h $SAMPLE_DEM | cut -f1))"

# Step 3: Check if container image exists
echo "📋 Step 3: Checking container images..."

if ! docker images | grep -q "eemt.*ubuntu24.04"; then
    echo "⚠️  EEMT container not found. Building now..."
    echo "This may take 10-30 minutes depending on your system..."
    
    cd docker/ubuntu/24.04/
    ./build.sh
    cd ../../..
    
    echo "✅ Container built successfully"
else
    echo "✅ EEMT container found"
fi

# Step 4: Prepare test environment
echo "📋 Step 4: Setting up test environment..."

# Create data directories
mkdir -p data/{uploads,results,temp,cache,shared}

# Copy sample DEM to uploads
cp "$SAMPLE_DEM" data/uploads/

echo "✅ Test environment prepared"

# Step 5: Start web interface
echo "📋 Step 5: Starting EEMT web interface..."

# Stop any existing containers
docker stop eemt-test-web 2>/dev/null || true
docker rm eemt-test-web 2>/dev/null || true

# Check if web interface container exists
if ! docker images | grep -q "eemt-web"; then
    echo "⚠️  Building web interface container..."
    docker build -t eemt-web -f docker/web-interface/Dockerfile .
fi

# Start web interface container
docker run -d \
    --name eemt-test-web \
    -p $WEB_PORT:5000 \
    -v $(pwd)/data:/app/data \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e PYTHONUNBUFFERED=1 \
    eemt-web

# Wait for service to start
echo "⏳ Waiting for web interface to start..."
sleep 10

# Check if service is running
if curl -s -f "http://localhost:$WEB_PORT/api/system/status" > /dev/null; then
    echo "✅ Web interface started successfully"
else
    echo "❌ Web interface failed to start. Checking logs..."
    docker logs eemt-test-web
    exit 1
fi

# Step 6: Display access information
echo ""
echo "🎉 EEMT Test Deployment Complete!"
echo "================================="
echo ""
echo "📍 Access Points:"
echo "   Web Interface: http://localhost:$WEB_PORT"
echo "   Job Monitor:   http://localhost:$WEB_PORT/monitor"
echo "   API Docs:      http://localhost:$WEB_PORT/docs"
echo ""
echo "📊 System Status:"
curl -s "http://localhost:$WEB_PORT/api/system/status" | python3 -m json.tool
echo ""
echo "🧪 Test Workflow:"
echo "   1. Open http://localhost:$WEB_PORT in your browser"
echo "   2. Upload the sample DEM (mcn_10m.tif) - already copied to uploads/"
echo "   3. Select 'Solar Radiation' workflow"
echo "   4. Configure parameters:"
echo "      - Time Step: 15 minutes"
echo "      - CPU Threads: 2 (for testing)"
echo "      - Linke Turbidity: 3.0"
echo "      - Surface Albedo: 0.2"
echo "   5. Submit job and monitor progress"
echo ""
echo "🔧 Management Commands:"
echo "   View logs:        docker logs -f eemt-test-web"
echo "   Stop deployment:  docker stop eemt-test-web"
echo "   Cleanup:          docker rm eemt-test-web"
echo ""
echo "📁 Data Locations:"
echo "   Uploads:   $(pwd)/data/uploads/"
echo "   Results:   $(pwd)/data/results/"
echo "   Temp:      $(pwd)/data/temp/"
echo ""

# Optional: Start a sample job via API
read -p "🤖 Submit a test job via API? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📤 Submitting test job via REST API..."
    
    RESPONSE=$(curl -s -X POST "http://localhost:$WEB_PORT/api/submit-job" \
        -F "workflow_type=sol" \
        -F "dem_file=@data/uploads/mcn_10m.tif" \
        -F "step=15" \
        -F "num_threads=2" \
        -F "linke_value=3.0" \
        -F "albedo_value=0.2")
    
    JOB_ID=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['job_id'])")
    
    echo "✅ Job submitted successfully: $JOB_ID"
    echo "📊 Monitor progress at: http://localhost:$WEB_PORT/monitor"
    echo "🔍 Job details: http://localhost:$WEB_PORT/api/jobs/$JOB_ID"
fi

echo ""
echo "🏁 Test deployment ready! Press Ctrl+C to stop when done testing."

# Keep script running to monitor
trap 'echo ""; echo "🛑 Stopping test deployment..."; docker stop eemt-test-web; docker rm eemt-test-web; echo "✅ Cleanup complete"; exit 0' INT

# Monitor container status
while true; do
    if ! docker ps | grep -q eemt-test-web; then
        echo "❌ Container stopped unexpectedly"
        break
    fi
    sleep 30
done