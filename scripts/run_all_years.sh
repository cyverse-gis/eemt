#!/bin/bash
# Run EEMT daily analysis for all DAYMET years (1980-2024)
# First computes shared inputs (slope, TWI, dem_1km), then runs years in parallel.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_BASE="/opt/tswetnam/data/gordon_gulch/eemt_smoke_test"
MAX_PARALLEL=${1:-4}

echo "EEMT Full Record Analysis — Gordon Gulch 1980-2024"
echo "=================================================="
echo "Start: $(date)"
echo "Parallel: ${MAX_PARALLEL} at a time"
echo ""

# Step 1: Compute shared inputs with a single run (avoid race conditions)
echo "[INIT] Computing shared inputs (slope, TWI, dem_1km)..."
python3 "${SCRIPT_DIR}/eemt_smoke_test.py" --year 1980 --daily --per-year-output 2>&1 | head -20
echo "[INIT] Shared inputs ready"
echo ""

# Step 2: Run remaining years in parallel (shared inputs are cached)
mkdir -p "${OUTPUT_BASE}/yearly_stats"

run_year() {
    local year=$1
    local csv="${OUTPUT_BASE}/yearly_stats/stats_${year}.csv"
    local log="${OUTPUT_BASE}/yearly_stats/log_${year}.txt"

    # Skip if already completed
    if [ -f "$csv" ] && [ $(wc -l < "$csv") -ge 13 ]; then
        echo "[SKIP] ${year}"
        return 0
    fi

    python3 "${SCRIPT_DIR}/eemt_smoke_test.py" --year "$year" --daily \
        --per-year-output --quiet > "$log" 2>&1
    rc=$?

    if [ $rc -eq 0 ]; then
        local year_csv="${OUTPUT_BASE}/${year}/monthly_stats.csv"
        if [ -f "$year_csv" ]; then
            cp "$year_csv" "$csv"
        fi
        # Print the summary line from the log
        grep "^${year}:" "$log" 2>/dev/null || echo "[DONE] ${year}"
    else
        echo "[FAIL] ${year} (exit $rc)"
        tail -3 "$log" 2>/dev/null
    fi
    return $rc
}

export -f run_year
export SCRIPT_DIR OUTPUT_BASE

# Run years in parallel batches
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
echo ""

# Summary
completed=$(ls -1 "${OUTPUT_BASE}/yearly_stats/stats_*.csv" 2>/dev/null | wc -l)
total_size=$(du -sh "${OUTPUT_BASE}" 2>/dev/null | cut -f1)
echo "Completed: ${completed}/45 years"
echo "Total size: ${total_size}"

# Run multi-year report if enough data
if [ $completed -ge 10 ]; then
    echo ""
    echo "Generating multi-year summary report..."
    python3 "${SCRIPT_DIR}/eemt_multiyear_report.py"
fi
