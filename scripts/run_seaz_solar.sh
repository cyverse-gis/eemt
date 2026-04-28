#!/bin/bash
# Run 365-day r.sun solar radiation for SE Arizona DEM
# Uses GRASS GIS 8.4 in --tmp-project session mode
#
# Output: /opt/tswetnam/data/seaz/10m/dem/global/daily/total_sun_day_*.tif
#         /opt/tswetnam/data/seaz/10m/dem/insol/daily/hours_sun_day_*.tif
#         /opt/tswetnam/data/seaz/10m/dem/global/monthly/total_sun_*_sum.tif
#         /opt/tswetnam/data/seaz/10m/dem/insol/monthly/hours_sun_*_sum.tif

set -e

DEM="/opt/tswetnam/data/seaz/seaz_dem_10m.tif"
OUTDIR="/opt/tswetnam/data/seaz/10m/dem"
STEP=15
LINKE=3.0
ALBEDO=0.2
NPROCS=16          # r.sun internal threads per day
MAX_PARALLEL=${1:-8}  # concurrent day computations

echo "SEAZ Solar Radiation Pipeline"
echo "============================="
echo "DEM: $DEM (8004x9989, 10m, UTM 12N)"
echo "Step: $STEP min, Linke: $LINKE, Albedo: $ALBEDO"
echo "r.sun nprocs: $NPROCS, parallel days: $MAX_PARALLEL"
echo "Start: $(date)"
echo ""

mkdir -p "$OUTDIR"/{global/{daily,monthly,annual},insol/{daily,monthly,annual}}

# Pre-compute slope and aspect once
SLOPE="$OUTDIR/slope_dec.tif"
ASPECT="$OUTDIR/aspect_dec.tif"

if [ ! -f "$SLOPE" ] || [ ! -f "$ASPECT" ]; then
    echo "[PREP] Computing slope and aspect..."
    grass --tmp-project EPSG:32612 --exec bash -c "
        r.in.gdal input=$DEM output=dem -o
        g.region -sa raster=dem
        r.slope.aspect elevation=dem slope=slope_dec aspect=aspect_dec
        r.out.gdal createopt='COMPRESS=LZW' -c input=slope_dec output=$SLOPE
        r.out.gdal createopt='COMPRESS=LZW' -c input=aspect_dec output=$ASPECT
    " 2>&1 | grep -v "^$"
    echo "[PREP] Slope and aspect computed."
else
    echo "[PREP] Slope and aspect already exist (cached)."
fi

# Function to run r.sun for a single day
run_day() {
    local day=$1
    local glob_out="$OUTDIR/global/daily/total_sun_day_${day}.tif"
    local insol_out="$OUTDIR/insol/daily/hours_sun_day_${day}.tif"

    if [ -f "$glob_out" ] && [ -f "$insol_out" ]; then
        return 0
    fi

    grass --tmp-project EPSG:32612 --exec bash -c "
        r.in.gdal input=$DEM output=dem -o 2>/dev/null
        r.in.gdal input=$SLOPE output=slope_dec -o 2>/dev/null
        r.in.gdal input=$ASPECT output=aspect_dec -o 2>/dev/null
        g.region -sa raster=dem 2>/dev/null
        r.sun elevation=dem aspect=aspect_dec slope=slope_dec \
            day=$day step=$STEP linke_value=$LINKE albedo_value=$ALBEDO \
            insol_time=hours_sun glob_rad=total_sun nprocs=$NPROCS 2>/dev/null
        r.out.gdal createopt='COMPRESS=LZW' -c input=total_sun output=$glob_out 2>/dev/null
        r.out.gdal createopt='COMPRESS=LZW' -c input=hours_sun output=$insol_out 2>/dev/null
    " 2>/dev/null

    if [ -f "$glob_out" ]; then
        echo "  Day $day: done"
    else
        echo "  Day $day: FAILED"
    fi
}

# Run all 365 days with parallel throttling
echo ""
echo "[SOLAR] Running r.sun for 365 days..."
active=0
for day in $(seq 1 365); do
    run_day $day &
    active=$((active + 1))
    if [ $active -ge $MAX_PARALLEL ]; then
        wait -n 2>/dev/null || wait
        active=$((active - 1))
    fi
done
wait

# Count completed
completed=$(ls "$OUTDIR/global/daily/total_sun_day_"*.tif 2>/dev/null | wc -l)
echo ""
echo "[SOLAR] Completed: $completed/365 daily files"

# Monthly aggregation
echo ""
echo "[AGGREGATE] Computing monthly sums..."

# Month name, start day, number of days
declare -A MONTH_START=(
    [jan]=1  [feb]=32 [mar]=60  [apr]=91  [may]=121 [jun]=152
    [jul]=182 [aug]=213 [sep]=244 [oct]=274 [nov]=305 [dec]=335
)
declare -A MONTH_DAYS=(
    [jan]=31 [feb]=28 [mar]=31 [apr]=30 [may]=31 [jun]=30
    [jul]=31 [aug]=31 [sep]=30 [oct]=31 [nov]=30 [dec]=31
)

for month in jan feb mar apr may jun jul aug sep oct nov dec; do
    start=${MONTH_START[$month]}
    ndays=${MONTH_DAYS[$month]}
    end=$((start + ndays - 1))

    glob_monthly="$OUTDIR/global/monthly/total_sun_${month}_sum.tif"
    insol_monthly="$OUTDIR/insol/monthly/hours_sun_${month}_sum.tif"

    if [ -f "$glob_monthly" ] && [ -f "$insol_monthly" ]; then
        echo "  $month: cached"
        continue
    fi

    # Build list of daily files for this month
    glob_files=""
    insol_files=""
    for d in $(seq $start $end); do
        glob_files="$glob_files $OUTDIR/global/daily/total_sun_day_${d}.tif"
        insol_files="$insol_files $OUTDIR/insol/daily/hours_sun_day_${d}.tif"
    done

    # Sum using GRASS r.series
    grass --tmp-project EPSG:32612 --exec bash -c "
        i=1
        for f in $glob_files; do
            r.in.gdal input=\$f output=glob_\$i -o 2>/dev/null
            i=\$((i+1))
        done
        g.region -sa raster=glob_1 2>/dev/null
        input_list=\$(g.list type=raster pattern='glob_*' separator=comma)
        r.series input=\$input_list output=glob_sum method=sum 2>/dev/null
        r.out.gdal createopt='COMPRESS=LZW' -c input=glob_sum output=$glob_monthly 2>/dev/null
    " 2>/dev/null

    grass --tmp-project EPSG:32612 --exec bash -c "
        i=1
        for f in $insol_files; do
            r.in.gdal input=\$f output=insol_\$i -o 2>/dev/null
            i=\$((i+1))
        done
        g.region -sa raster=insol_1 2>/dev/null
        input_list=\$(g.list type=raster pattern='insol_*' separator=comma)
        r.series input=\$input_list output=insol_sum method=sum 2>/dev/null
        r.out.gdal createopt='COMPRESS=LZW' -c input=insol_sum output=$insol_monthly 2>/dev/null
    " 2>/dev/null

    echo "  $month: done (days $start-$end)"
done

echo ""
echo "Finished: $(date)"
echo "Solar outputs: $OUTDIR"
