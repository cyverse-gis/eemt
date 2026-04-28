#!/bin/bash
# Run full EEMT analysis on the Pinaleño 10m DEM, 1980-2024.
# Wraps eemt_smoke_test.py with paths overridden for the Pinaleño dataset.
#
# Usage:
#   ./run_pinaleno_eemt.sh          # default MAX_PARALLEL=16
#   ./run_pinaleno_eemt.sh 31

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEM="/home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif"
SOLAR="/home/tswetnam/data/pinaleno/solar/10m/dem"
DAYMET="/home/tswetnam/data/pinaleno/daymet/daily"
OUTPUT="/home/tswetnam/data/pinaleno/eemt"
MAX_PARALLEL=${1:-16}

export PROJ_DATA=/home/tswetnam/miniforge3/share/proj

echo "EEMT Full Analysis — Pinaleño + Santa Teresa Mts (1980-2024)"
echo "============================================================="
echo "DEM: 6147x7259 (~62km x 73km, 10m, UTM 12N)"
echo "Elevation: 785-3264m (San Pedro Valley to Mt Graham summit)"
echo "Start: $(date)"
echo "Parallel: ${MAX_PARALLEL}"
echo ""

# Create runner that overrides paths in the smoke test
cat > /tmp/eemt_pinaleno_runner.py << 'PYEOF'
import sys
sys.path.insert(0, "/home/tswetnam/github/eemt/scripts")

import eemt_smoke_test as est
est.DEM_PATH = "/home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif"
est.SOLAR_DIR = "/home/tswetnam/data/pinaleno/solar/10m/dem"
est.DAYMET_DIR = "/home/tswetnam/data/pinaleno/daymet/daily"
est.OUTPUT_DIR = "/home/tswetnam/data/pinaleno/eemt"

est.main()
PYEOF

# Step 1: Compute shared inputs with first year (1980)
echo "[INIT] Computing shared inputs on 1980..."
python3 /tmp/eemt_pinaleno_runner.py --year 1980 --daily --per-year-output 2>&1 \
    | grep -E "^\[|DEM:|slope|TWI|dem_1km|EEMT|Phase|Completed|1980:"
echo ""

# Step 2: Remaining years in parallel
mkdir -p "${OUTPUT}/yearly_stats"

run_year() {
    local year=$1
    local csv="${OUTPUT}/yearly_stats/stats_${year}.csv"
    local log="${OUTPUT}/yearly_stats/log_${year}.txt"

    if [ -f "$csv" ] && [ "$(wc -l < "$csv")" -ge 13 ]; then
        return 0
    fi

    python3 /tmp/eemt_pinaleno_runner.py --year "$year" --daily \
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
    if [ "$active" -ge "$MAX_PARALLEL" ]; then
        wait -n 2>/dev/null || wait
        active=$((active - 1))
    fi
done
wait

echo ""
echo "Finished: $(date)"
completed=$(ls "${OUTPUT}/yearly_stats/stats_"*.csv 2>/dev/null | wc -l)
echo "Completed: ${completed}/45 years"
