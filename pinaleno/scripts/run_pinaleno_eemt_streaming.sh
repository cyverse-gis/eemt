#!/bin/bash
# Streaming EEMT for Pinaleño 1980-2024 — one day at a time, ~5-10 GB RAM/process.
# Uses /home/tswetnam/github/eemt/scripts/seaz_eemt_streaming.py with paths overridden.

set -e

DEM="/home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif"
SOLAR="/home/tswetnam/data/pinaleno/solar/10m/dem"
DAYMET="/home/tswetnam/data/pinaleno/daymet/daily"
OUTPUT="/home/tswetnam/data/pinaleno/eemt"
MAX_PARALLEL=${1:-12}

# Streaming runner
cat > /tmp/eemt_pinaleno_streaming.py << 'PYEOF'
import sys
sys.path.insert(0, "/home/tswetnam/github/eemt/scripts")
import seaz_eemt_streaming as st
st.DEM_PATH = "/home/tswetnam/data/pinaleno/dem/pinaleno_dem_10m.tif"
st.SOLAR_DIR = "/home/tswetnam/data/pinaleno/solar/10m/dem"
st.DAYMET_DIR = "/home/tswetnam/data/pinaleno/daymet/daily"
st.OUTPUT_DIR = "/home/tswetnam/data/pinaleno/eemt"
st.main()
PYEOF

echo "EEMT Streaming Analysis — Pinaleño + Santa Teresa Mts (1980-2024)"
echo "=================================================================="
echo "DEM: 6147x7259 (10m, UTM 12N, 785-3264m)"
echo "Mode: streaming (one day at a time, ~5-10 GB/process)"
echo "Parallel: ${MAX_PARALLEL}"
echo "Start: $(date)"
echo ""

mkdir -p "${OUTPUT}/yearly_stats"

run_year() {
    local year=$1
    local csv="${OUTPUT}/yearly_stats/stats_${year}.csv"
    local log="${OUTPUT}/yearly_stats/log_${year}.txt"

    if [ -f "$csv" ] && [ "$(wc -l < "$csv")" -ge 13 ]; then
        return 0
    fi

    python3 /tmp/eemt_pinaleno_streaming.py --year "$year" --per-year-output --quiet \
        > "$log" 2>&1
    rc=$?

    if [ $rc -eq 0 ]; then
        local year_csv="${OUTPUT}/${year}/monthly_stats.csv"
        [ -f "$year_csv" ] && cp "$year_csv" "$csv"
        grep "^${year}:" "$log" 2>/dev/null
    else
        echo "[FAIL] ${year} (exit $rc) — see $log"
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
