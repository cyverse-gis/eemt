#!/bin/bash
# Docker build script for EEMT Ubuntu 24.04

set -e

# Configuration
IMAGE_NAME="eemt"
TAG="ubuntu24.04"

# Change to repository root for proper build context
cd "$(dirname "$0")/../../.."

echo "Building EEMT Docker image: ${IMAGE_NAME}:${TAG}"
echo "Build context: $(pwd)"
echo "Dockerfile: docker/ubuntu/24.04/Dockerfile"

# Optional: Add build cache optimization
CACHE_FROM=""
if docker images -q ${IMAGE_NAME}:${TAG} >/dev/null 2>&1; then
    CACHE_FROM="--cache-from ${IMAGE_NAME}:${TAG}"
    echo "Using cache from existing image"
fi

# Build the Docker image with correct context
echo "Starting Docker build..."
docker build \
    ${CACHE_FROM} \
    -t ${IMAGE_NAME}:${TAG} \
    -f docker/ubuntu/24.04/Dockerfile \
    .

echo "Build completed successfully!"
echo "Image: ${IMAGE_NAME}:${TAG}"

# Display image size
echo ""
echo "Image details:"
docker images ${IMAGE_NAME}:${TAG}

echo ""
echo "Test the image with:"
echo "  docker run -it --rm ${IMAGE_NAME}:${TAG}"
echo ""
echo "Test GRASS GIS:"
echo "  docker run --rm ${IMAGE_NAME}:${TAG} grass --version"
echo ""
echo "Test CCTools:"
echo "  docker run --rm ${IMAGE_NAME}:${TAG} makeflow --version"
echo ""
echo "Test EEMT workflows:"
echo "  docker run --rm ${IMAGE_NAME}:${TAG} python /opt/eemt/bin/run-solar-workflow.py --help"