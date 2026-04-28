#!/bin/bash
# Download USGS 3DEP 1/3 arc-second (~10m) DEM for Pinaleño + Santa Teresa Mts
#
# Pinaleño Mountains:    32.55-32.85 N, -110.10 to -109.80 W (Mt Graham 3267m)
# Santa Teresa Mountains: 32.85-33.10 N, -110.30 to -110.05 W (NW extension)
#
# Combined bbox (with buffer): 32.50-33.15 N, -110.40 to -109.75 W
# Required 1x1° tiles: n33w110, n34w110, n33w111, n34w111
#
# Output: /home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif (UTM 12N COG)

set -e

DATA_DIR="/home/tswetnam/data/pinaleno/dem"
TILES_DIR="${DATA_DIR}/tiles"
mkdir -p "$TILES_DIR"

# Bounding box (WGS84) - covers full Pinaleño + Santa Teresa range
NORTH=33.15
SOUTH=32.50
WEST=-110.40
EAST=-109.75

# UTM 12N target bounds (will be computed by gdalwarp -te_srs)
TARGET_SRS="EPSG:32612"
TARGET_RES=10

USGS_BASE="https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current"

TILES=("n33w110" "n34w110" "n33w111" "n34w111")

echo "Pinaleño 10m DEM Download"
echo "=========================="
echo "Bbox: W=$WEST S=$SOUTH E=$EAST N=$NORTH (WGS84)"
echo "Tiles: ${TILES[*]}"
echo "Output SRS: $TARGET_SRS @ ${TARGET_RES}m"
echo "Start: $(date)"
echo ""

# 1. Download tiles
for tile in "${TILES[@]}"; do
    out="${TILES_DIR}/USGS_13_${tile}.tif"
    if [ -f "$out" ] && [ "$(stat -c%s "$out")" -gt 1000000 ]; then
        echo "[CACHE] $tile already downloaded ($(du -h "$out" | cut -f1))"
        continue
    fi
    url="${USGS_BASE}/${tile}/USGS_13_${tile}.tif"
    echo "[DOWNLOAD] $tile from $url"
    curl -fsSL --retry 3 -o "$out" "$url" || {
        echo "  FAILED: $tile (HTTP error or missing tile)"
        rm -f "$out"
    }
    if [ -f "$out" ]; then
        echo "  Done: $(du -h "$out" | cut -f1)"
    fi
done

echo ""
echo "[MOSAIC] Building VRT..."
VRT="${DATA_DIR}/pinaleno_mosaic.vrt"
gdalbuildvrt -overwrite "$VRT" "${TILES_DIR}"/USGS_13_*.tif

echo ""
echo "[WARP] Reprojecting to UTM 12N @ ${TARGET_RES}m, clipping to bbox..."
OUT_TIF="${DATA_DIR}/pinaleno_dem_10m.tif"
gdalwarp -overwrite \
    -t_srs "$TARGET_SRS" \
    -te_srs "EPSG:4326" \
    -te "$WEST" "$SOUTH" "$EAST" "$NORTH" \
    -tr $TARGET_RES $TARGET_RES \
    -r bilinear \
    -of COG \
    -co COMPRESS=LZW \
    -co BLOCKSIZE=512 \
    -co OVERVIEWS=AUTO \
    -co RESAMPLING=AVERAGE \
    -co NUM_THREADS=ALL_CPUS \
    "$VRT" \
    "$OUT_TIF"

echo ""
echo "[INFO] Output DEM:"
gdalinfo "$OUT_TIF" | head -25

echo ""
echo "Finished: $(date)"
echo "DEM: $OUT_TIF ($(du -h "$OUT_TIF" | cut -f1))"
