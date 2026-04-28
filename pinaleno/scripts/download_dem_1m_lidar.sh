#!/bin/bash
# STAGED — DO NOT RUN UNTIL DISK SPACE IS AVAILABLE
#
# Download USGS 3DEP 1m lidar DEM tiles for Pinaleño + Santa Teresa Mountains.
#
# Estimated footprint: ~30-50 GB raw / 8-15 GB COG-LZW for full mountain range.
# Requires the /opt/tswetnam mount (or alternate ≥100 GB volume) since /home
# is reserved for active 10m work.
#
# Strategy:
#   1. Query USGS TNM (The National Map) Access API for 1m project tiles
#      intersecting the Pinaleño bbox.
#   2. Filter to recent USGS lidar projects covering the mountains
#      (likely AZ_USGS_LowerCo_2019 or AZ_GilaRiver_2020 collections).
#   3. Download each tile (1km x 1km IMG/TIFF).
#   4. Mosaic to VRT, then warp to UTM 12N COG @ 1m.
#
# Bounding box (WGS84): 32.50-33.15 N, -110.40 to -109.75 W

set -e

DATA_DIR="${PINALENO_LIDAR_DIR:-/home/tswetnam/data/pinaleno/lidar_1m}"
TILES_DIR="${DATA_DIR}/tiles"
INDEX_JSON="${DATA_DIR}/tnm_index.json"
mkdir -p "$TILES_DIR"

NORTH=33.15
SOUTH=32.50
WEST=-110.40
EAST=-109.75

# USGS TNM Access API endpoint for 1m DEM products
# datasets=Lidar Point Cloud (LPC), or "Digital Elevation Model (DEM) 1 meter"
TNM_API="https://tnmaccess.nationalmap.gov/api/v1/products"
DATASET="Digital Elevation Model (DEM) 1 meter"

echo "Pinaleño 1m LIDAR DEM Stage Script"
echo "==================================="
echo "Bbox: W=$WEST S=$SOUTH E=$EAST N=$NORTH"
echo "Output: $DATA_DIR"
echo ""

# Disk space check — bail out if less than 100 GB free
AVAIL_KB=$(df -P "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
if [ "$AVAIL_GB" -lt 100 ]; then
    echo "ERROR: Only ${AVAIL_GB} GB free at $DATA_DIR — need ≥100 GB."
    echo "Free space or set PINALENO_LIDAR_DIR to a larger volume."
    exit 1
fi
echo "[DISK] ${AVAIL_GB} GB free — OK to proceed"
echo ""

# 1. Query TNM Access API for 1m DEM tiles in bbox
echo "[QUERY] Fetching tile index from TNM Access API..."
curl -fsSL \
    --data-urlencode "datasets=${DATASET}" \
    --data-urlencode "bbox=${WEST},${SOUTH},${EAST},${NORTH}" \
    --data-urlencode "max=1000" \
    --data-urlencode "outputFormat=JSON" \
    -G "$TNM_API" \
    -o "$INDEX_JSON"

NUM_TILES=$(python3 -c "import json; d=json.load(open('$INDEX_JSON')); print(len(d.get('items', [])))")
echo "  Found $NUM_TILES 1m tiles"
echo ""

if [ "$NUM_TILES" -eq 0 ]; then
    echo "WARNING: No 1m tiles found. Check TNM coverage at:"
    echo "  https://apps.nationalmap.gov/downloader/"
    exit 1
fi

# 2. Extract download URLs and titles
python3 - <<PYEOF > "${DATA_DIR}/download_list.txt"
import json
with open("$INDEX_JSON") as f:
    d = json.load(f)
for item in d.get("items", []):
    url = item.get("downloadURL") or item.get("urls", {}).get("TIFF") or item.get("urls", {}).get("IMG")
    title = item.get("title", "unknown")
    if url:
        print(f"{url}\t{title}")
PYEOF

NUM_URLS=$(wc -l < "${DATA_DIR}/download_list.txt")
echo "  $NUM_URLS downloadable tiles"
echo ""

# 3. Download tiles in parallel (8 concurrent)
echo "[DOWNLOAD] Pulling tiles to $TILES_DIR..."
cat "${DATA_DIR}/download_list.txt" | while IFS=$'\t' read -r url title; do
    fname=$(basename "$url")
    out="${TILES_DIR}/${fname}"
    if [ -f "$out" ] && [ "$(stat -c%s "$out")" -gt 100000 ]; then
        continue
    fi
    echo "  $fname"
    curl -fsSL --retry 3 -o "$out" "$url" || echo "    FAILED: $title"
done

# 4. Mosaic and reproject to UTM 12N @ 1m
echo ""
echo "[MOSAIC] Building VRT..."
gdalbuildvrt -overwrite "${DATA_DIR}/pinaleno_lidar_mosaic.vrt" \
    "${TILES_DIR}"/*.tif "${TILES_DIR}"/*.img 2>/dev/null

echo "[WARP] Reprojecting to UTM 12N @ 1m COG..."
gdalwarp -overwrite \
    -t_srs EPSG:32612 \
    -te_srs EPSG:4326 \
    -te "$WEST" "$SOUTH" "$EAST" "$NORTH" \
    -tr 1 1 \
    -r bilinear \
    -of COG \
    -co COMPRESS=LZW \
    -co BLOCKSIZE=512 \
    -co OVERVIEWS=AUTO \
    -co RESAMPLING=AVERAGE \
    -co NUM_THREADS=ALL_CPUS \
    "${DATA_DIR}/pinaleno_lidar_mosaic.vrt" \
    "${DATA_DIR}/pinaleno_dem_1m.tif"

echo ""
echo "Finished: $(date)"
echo "1m DEM: ${DATA_DIR}/pinaleno_dem_1m.tif"
du -h "${DATA_DIR}/pinaleno_dem_1m.tif"
