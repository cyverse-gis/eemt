#!/bin/bash
# Compare rsun (Rust) output against GRASS r.sun output on mcn_10m.tif
#
# Prerequisites:
#   - rsun binary built: cd rsun && cargo build --release --features io
#   - eemt:ubuntu24.04 Docker image available
#   - GDAL tools (gdalinfo, gdal_calc.py) available
#
# Usage: cd rsun && bash validation/compare.sh

set -e

DEM="../sol/examples/mcn_10m.tif"
DAYS="1 91 172 274"  # winter solstice, spring equinox, summer solstice, fall equinox
STEP=0.5
LINKE=3.0
ALBEDO=0.2
OUTDIR="/tmp/rsun_validation"

mkdir -p "$OUTDIR/rsun" "$OUTDIR/grass"

echo "=== rsun Validation: comparing Rust vs GRASS r.sun ==="
echo "DEM: $DEM"
echo "Days: $DAYS"
echo "Step: $STEP, Linke: $LINKE, Albedo: $ALBEDO"
echo ""

# --- Run rsun (Rust) ---
echo "=== Running rsun (Rust) ==="
for DAY in $DAYS; do
    echo "  Day $DAY..."
    cargo run --release --bin rsun -- compute \
        --dem "$DEM" --day "$DAY" --step "$STEP" \
        --linke "$LINKE" --albedo "$ALBEDO" \
        --glob-rad "$OUTDIR/rsun/glob_rad_day_${DAY}.tif" \
        --insol-time "$OUTDIR/rsun/insol_time_day_${DAY}.tif" 2>/dev/null
done
echo "  Done."
echo ""

# --- Run GRASS r.sun (via Docker) ---
echo "=== Running GRASS r.sun (via Docker) ==="
for DAY in $DAYS; do
    echo "  Day $DAY..."
    docker run --rm \
        -v "$(cd .. && pwd)/sol/examples:/data/input:ro" \
        -v "$OUTDIR/grass:/data/output:rw" \
        eemt:ubuntu24.04 bash -c "
            WORKING_DIR=\$RANDOM
            LOCATION=/data/output/tmp_\${WORKING_DIR}/PERMANENT
            GRASSRC=/data/output/.grassrc_\${WORKING_DIR}
            export GISRC=\$GRASSRC
            export GRASS_VERBOSE=0
            mkdir -p \$LOCATION
            cat > \"\${LOCATION}/DEFAULT_WIND\" << __EOF__
proj: 99
zone: 0
north: 1
south: 0
east: 1
west: 0
cols: 1
rows: 1
e-w resol: 1
n-s resol: 1
top: 1.000000000000000
bottom: 0.000000000000000
cols3: 1
rows3: 1
depths: 1
e-w resol3: 1
n-s resol3: 1
t-b resol: 1
__EOF__
            cp \${LOCATION}/DEFAULT_WIND \${LOCATION}/WIND
            echo \"GISDBASE: /data/output\" > \$GRASSRC
            echo \"LOCATION_NAME: tmp_\${WORKING_DIR}\" >> \$GRASSRC
            echo \"MAPSET: PERMANENT\" >> \$GRASSRC
            echo \"GRASS_GUI: text\" >> \$GRASSRC
            g.proj -c georef=/data/input/mcn_10m.tif
            r.in.gdal input=/data/input/mcn_10m.tif output=dem
            g.region -sa raster=dem
            r.slope.aspect elevation=dem slope=slope_dec aspect=aspect_dec
            r.sun elevation=dem aspect=aspect_dec slope=slope_dec \
                day=$DAY step=$STEP linke_value=$LINKE albedo_value=$ALBEDO \
                glob_rad=total_sun insol_time=hours_sun nprocs=4
            r.out.gdal createopt=\"COMPRESS=LZW\" -c input=total_sun \
                output=/data/output/glob_rad_day_${DAY}.tif
            r.out.gdal createopt=\"COMPRESS=LZW\" -c input=hours_sun \
                output=/data/output/insol_time_day_${DAY}.tif
            rm -rf /data/output/tmp_\${WORKING_DIR}/ \$GRASSRC
        " 2>/dev/null
done
echo "  Done."
echo ""

# --- Compare outputs ---
echo "=== Comparison Results ==="
echo ""
printf "%-6s  %-12s  %-12s  %-12s  %-12s  %-8s\n" \
    "Day" "rsun_mean" "grass_mean" "RMSE" "MaxRelErr%" "Status"
echo "------  ----------  ----------  ----------  ----------  --------"

for DAY in $DAYS; do
    RSUN_FILE="$OUTDIR/rsun/glob_rad_day_${DAY}.tif"
    GRASS_FILE="$OUTDIR/grass/glob_rad_day_${DAY}.tif"

    if [ ! -f "$GRASS_FILE" ]; then
        echo "Day $DAY: GRASS output missing (Docker not available?)"
        continue
    fi

    python3 - "$RSUN_FILE" "$GRASS_FILE" "$DAY" << 'PYEOF'
import sys
import numpy as np

try:
    from osgeo import gdal
except ImportError:
    print("  gdal python bindings not available, skipping quantitative comparison")
    sys.exit(0)

rsun_file, grass_file, day = sys.argv[1], sys.argv[2], sys.argv[3]

ds1 = gdal.Open(rsun_file)
ds2 = gdal.Open(grass_file)
r1 = ds1.GetRasterBand(1).ReadAsArray().astype(np.float64)
r2 = ds2.GetRasterBand(1).ReadAsArray().astype(np.float64)

nd1 = ds1.GetRasterBand(1).GetNoDataValue()
nd2 = ds2.GetRasterBand(1).GetNoDataValue()

# Mask nodata
mask = np.ones_like(r1, dtype=bool)
if nd1 is not None:
    mask &= r1 != nd1
if nd2 is not None:
    mask &= r2 != nd2
mask &= ~np.isnan(r1) & ~np.isnan(r2)
mask &= r2 > 0  # avoid division by zero

r1m, r2m = r1[mask], r2[mask]
diff = r1m - r2m
rmse = np.sqrt(np.mean(diff**2))
max_rel_err = np.max(np.abs(diff / r2m)) * 100
mean1, mean2 = np.mean(r1m), np.mean(r2m)

status = "PASS" if max_rel_err < 5.0 else "WARN" if max_rel_err < 10.0 else "FAIL"
print(f"{day:>6}  {mean1:>10.1f}  {mean2:>10.1f}  {rmse:>10.1f}  {max_rel_err:>10.2f}  {status:>8}")
PYEOF
done

echo ""
echo "Detailed outputs in: $OUTDIR/"
echo "  rsun:  $OUTDIR/rsun/"
echo "  GRASS: $OUTDIR/grass/"
