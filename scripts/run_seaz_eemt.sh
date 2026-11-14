#!/bin/bash
# Run full EEMT analysis on the SE Arizona 10m DEM
# Uses eemt_smoke_test.py with paths overridden for the SEAZ dataset
#
# Usage:
#   ./scripts/run_seaz_eemt.sh          # default MAX_PARALLEL=31
#   ./scripts/run_seaz_eemt.sh 15       # set MAX_PARALLEL=15

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEM="/opt/tswetnam/data/seaz/seaz_dem_10m.tif"
SOLAR="/opt/tswetnam/data/seaz/10m/dem"
DAYMET="/opt/tswetnam/data/seaz/daymet/daily"
OUTPUT="/opt/tswetnam/data/seaz/eemt"
MAX_PARALLEL=${1:-31}

export PROJ_DATA=/home/tswetnam/miniforge3/share/proj

echo "EEMT Full Analysis — SE Arizona (1980-2024)"
echo "============================================="
echo "DEM: 8004x9989 (80km x 100km, 10m, UTM 12N)"
echo "Elevation: 580-2880m (Tucson valley to Mt Lemmon)"
echo "Start: $(date)"
echo "Parallel: ${MAX_PARALLEL}"
echo ""

# Create a wrapper that overrides the paths in the smoke test
cat > /tmp/eemt_seaz_runner.py << 'PYEOF'
import sys
sys.path.insert(0, "/home/tswetnam/github/eemt/scripts")

# Override config before importing
import eemt_smoke_test as est
est.DEM_PATH = "/opt/tswetnam/data/seaz/seaz_dem_10m.tif"
est.SOLAR_DIR = "/opt/tswetnam/data/seaz/10m/dem"
est.DAYMET_DIR = "/opt/tswetnam/data/seaz/daymet/daily"
est.OUTPUT_DIR = "/opt/tswetnam/data/seaz/eemt"

# Run main
est.main()
PYEOF

# Step 1: Compute shared inputs with first year
echo "[INIT] Computing shared inputs on 1980..."
python3 /tmp/eemt_seaz_runner.py --year 1980 --daily --per-year-output 2>&1 | grep -E "^\[|DEM:|slope|TWI|dem_1km|EEMT|Phase|Completed|1980:"
echo ""

# Step 2: Run remaining years in parallel
mkdir -p "${OUTPUT}/yearly_stats"

run_year() {
    local year=$1
    local csv="${OUTPUT}/yearly_stats/stats_${year}.csv"
    local log="${OUTPUT}/yearly_stats/log_${year}.txt"

    if [ -f "$csv" ] && [ $(wc -l < "$csv") -ge 13 ]; then
        return 0
    fi

    python3 /tmp/eemt_seaz_runner.py --year "$year" --daily \
        --per-year-output --quiet > "$log" 2>&1
    rc=$?

    if [ $rc -eq 0 ]; then
        local year_csv="${OUTPUT}/${year}/monthly_stats.csv"
        [ -f "$year_csv" ] && cp "$year_csv" "$csv"
        grep "^${year}:" "$log" 2>/dev/null
    else
        echo "[FAIL] ${year} (exit $rc)"
    fi
}

active=0
for year in $(seq 1980 2024); do
    run_year "$year" &
    active=$((active + 1))
    if [ $active -ge $MAX_PARALLEL ]; then
        wait -n 2>/dev/null || wait
        active=$((active - 1))
    fi
done
wait

echo ""
echo "Finished: $(date)"
completed=$(ls "${OUTPUT}/yearly_stats/stats_"*.csv 2>/dev/null | wc -l)
echo "Completed: ${completed}/45 years"
