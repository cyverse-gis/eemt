#!/bin/bash
# Run EEMT for Pinaleño 1980-2024 with bounded parallelism.
# Caches stay on disk (BAND-interleave caches are tiny ~2 GB/year, /opt has 14 TB free).
#
# Logs: /opt/tswetnam/pinaleno/eemt/yearly_stats/log_<year>.txt
# Stats: /opt/tswetnam/pinaleno/eemt/yearly_stats/stats_<year>.csv
#
# Usage:
#   ./run_pinaleno_eemt_all.sh                       # 1980-2024, parallel=16
#   ./run_pinaleno_eemt_all.sh 1980 2024 8           # custom range + parallel
#   ./run_pinaleno_eemt_all.sh 2000 2010             # subset, default parallel

set -u

START_YEAR=${1:-1980}
END_YEAR=${2:-2024}
MAX_PARALLEL=${3:-16}
OUT="/opt/tswetnam/pinaleno/eemt"
RUNNER="/home/tswetnam/github/eemt/pinaleno/scripts/eemt_pinaleno_year.py"
STATS_DIR="${OUT}/yearly_stats"
mkdir -p "$STATS_DIR"

export PROJ_DATA=/home/tswetnam/miniforge3/share/proj

echo "EEMT Pinaleño — parallel ${START_YEAR}-${END_YEAR} (parallel=${MAX_PARALLEL})"
echo "Start: $(date)"
echo "Disk free: $(df -h /opt | awk 'NR==2 {print $4}')"
echo ""

run_year() {
    local year=$1
    local csv="${STATS_DIR}/stats_${year}.csv"
    local log="${STATS_DIR}/log_${year}.txt"

    if [ -f "$csv" ] && [ "$(wc -l < "$csv")" -ge 13 ]; then
        echo "[${year}] already done — skip"
        return 0
    fi

    local t0=$(date +%s)
    python3 "$RUNNER" --year "$year" --per-year-output --keep-cache > "$log" 2>&1
    local rc=$?
    local dt=$(( $(date +%s) - t0 ))

    if [ $rc -eq 0 ]; then
        local year_csv="${OUT}/${year}/monthly_stats.csv"
        [ -f "$year_csv" ] && cp "$year_csv" "$csv"
        local summary=$(grep "^${year}:" "$log" 2>/dev/null | tail -1)
        echo "[${year}] OK in ${dt}s — ${summary}"
    else
        echo "[${year}] FAIL exit=$rc in ${dt}s — see $log" >&2
    fi
}

export -f run_year
export STATS_DIR OUT RUNNER

active=0
for year in $(seq "$START_YEAR" "$END_YEAR"); do
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
done_count=$(ls "${STATS_DIR}/stats_"*.csv 2>/dev/null | wc -l)
total=$(( END_YEAR - START_YEAR + 1 ))
echo "Completed: ${done_count}/${total} years"
df -h /opt | tail -1
