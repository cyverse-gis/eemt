#!/bin/bash
# Run full EEMT analysis on the 16km Gordon Gulch expanded DEM
# Uses eemt_smoke_test.py with paths overridden for the 16km dataset

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEM="/opt/tswetnam/data/gordon_gulch_16km/gordon_gulch_16km_dem_10m.tif"
SOLAR="/opt/tswetnam/data/gordon_gulch_16km/10m/dem"
DAYMET="/opt/tswetnam/data/gordon_gulch_16km/daymet/daily"
OUTPUT="/opt/tswetnam/data/gordon_gulch_16km/eemt"
MAX_PARALLEL=${1:-31}

echo "EEMT Full Analysis — Gordon Gulch 16km (1980-2024)"
echo "==================================================="
echo "DEM: 1606x891 (16km x 9km, 10m)"
echo "Start: $(date)"
echo "Parallel: ${MAX_PARALLEL}"
echo ""

# Create a wrapper that overrides the paths in the smoke test
cat > /tmp/eemt_16km_runner.py << 'PYEOF'
import sys
sys.path.insert(0, "/home/tswetnam/github/eemt/scripts")

# Override config before importing
import eemt_smoke_test as est
est.DEM_PATH = "/opt/tswetnam/data/gordon_gulch_16km/gordon_gulch_16km_dem_10m.tif"
est.SOLAR_DIR = "/opt/tswetnam/data/gordon_gulch_16km/10m/dem"
est.DAYMET_DIR = "/opt/tswetnam/data/gordon_gulch_16km/daymet/daily"
est.OUTPUT_DIR = "/opt/tswetnam/data/gordon_gulch_16km/eemt"

# Run main
est.main()
PYEOF

# Step 1: Compute shared inputs with first year
echo "[INIT] Computing shared inputs on 1980..."
python3 /tmp/eemt_16km_runner.py --year 1980 --daily --per-year-output 2>&1 | grep -E "^\[|DEM:|slope|TWI|dem_1km|EEMT|Phase|Completed|1980:"
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

    python3 /tmp/eemt_16km_runner.py --year "$year" --daily \
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

# Generate summary report
if [ $completed -ge 10 ]; then
    echo ""
    echo "Generating multi-year report..."
    python3 -c "
import sys
sys.path.insert(0, '/home/tswetnam/github/eemt/scripts')
import eemt_multiyear_report as emr
emr.OUTPUT_BASE = '/opt/tswetnam/data/gordon_gulch_16km/eemt'
emr.main()
"
fi
