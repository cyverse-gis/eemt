#!/bin/bash
# Pre-compute TWI for Pinaleño 10m DEM using GRASS r.watershed (C, seconds vs hours).
# Output goes to the path eemt_smoke_test.py looks for, so its slow numpy D8
# code path is skipped via the on-disk cache check.

set -e

DEM="/home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif"
EEMT_DIR="/home/tswetnam/data/pinaleno/eemt"
INPUTS_DIR="${EEMT_DIR}/inputs"
TWI_OUT="${INPUTS_DIR}/twi.tif"
SLOPE_RAD="${INPUTS_DIR}/slope_rad.tif"

mkdir -p "$INPUTS_DIR"

if [ -f "$TWI_OUT" ]; then
    echo "[CACHE] TWI already exists: $TWI_OUT"
    gdalinfo -stats "$TWI_OUT" 2>/dev/null | grep STATISTICS
    exit 0
fi

echo "[GRASS] Computing flow accumulation + TWI..."
echo "Start: $(date)"

grass --tmp-project EPSG:32612 --exec bash -c "
    r.in.gdal input=$DEM output=dem -o
    g.region -sa raster=dem
    r.in.gdal input=$SLOPE_RAD output=slope_rad -o
    r.watershed elevation=dem accumulation=flow_acc threshold=10000 memory=8000
    # TWI = ln( (|flow_acc| * cell_area) / max(tan(slope_rad), 0.001) )
    r.mapcalc \"twi = log( (abs(flow_acc) * 100.0) / max(tan(slope_rad), 0.001) )\"
    r.out.gdal -c createopt='COMPRESS=LZW,TILED=YES' input=twi output=$TWI_OUT
"

echo ""
echo "Finished: $(date)"
gdalinfo -stats "$TWI_OUT" | grep -E "Size|STATISTICS"
echo "TWI: $TWI_OUT"
