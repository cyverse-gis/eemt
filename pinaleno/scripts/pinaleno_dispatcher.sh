#!/bin/bash
# Load-aware EEMT year dispatcher for Pinaleño.
#
# Polls system load every TICK seconds; launches one EEMT year if there
# are enough free cores and free RAM, and we are below MAX_OWN concurrent
# workers. Does not touch other users' processes. Exits when all years
# 1980..2024 (or the requested range) have a stats CSV with >= 13 lines.
#
# Designed for shared multi-user hosts: starts conservatively, scales up
# as cores free, never trips swap.
#
# Usage:
#   ./pinaleno_dispatcher.sh                                 # 1980-2024 with defaults
#   ./pinaleno_dispatcher.sh 1980 2024 8 10 40 30            # full args
#
# Args (all optional, with defaults):
#   $1 START_YEAR        1980
#   $2 END_YEAR          2024
#   $3 MAX_OWN           8     - never run more than this many of our workers
#   $4 MIN_FREE_CORES    10    - need (nproc - load1) >= this to launch
#   $5 MIN_FREE_GB       40    - need MemAvailable >= this many GB to launch
#   $6 TICK              30    - poll interval in seconds
#
# Logs:
#   $OUT/yearly_stats/dispatcher.log   - dispatcher decisions
#   $OUT/yearly_stats/log_<year>.txt   - per-year stdout/stderr

set -u

START_YEAR=${1:-1980}
END_YEAR=${2:-2024}
MAX_OWN=${3:-8}
MIN_FREE_CORES=${4:-10}
MIN_FREE_GB=${5:-40}
TICK=${6:-30}

OUT="/opt/tswetnam/pinaleno/eemt"
RUNNER="/home/tswetnam/github/eemt/pinaleno/scripts/eemt_pinaleno_year.py"
STATS_DIR="${OUT}/yearly_stats"
DISP_LOG="${STATS_DIR}/dispatcher.log"
mkdir -p "$STATS_DIR"

export PROJ_DATA=/home/tswetnam/miniforge3/share/proj

NCORES=$(nproc)

log() { echo "$(date '+%F %T') $*" | tee -a "$DISP_LOG"; }

log "=== dispatcher start: years ${START_YEAR}-${END_YEAR}, max_own=${MAX_OWN}, min_free_cores=${MIN_FREE_CORES}, min_free_gb=${MIN_FREE_GB}, tick=${TICK}s, host_cores=${NCORES} ==="

is_done() {
    local y=$1
    local csv="${STATS_DIR}/stats_${y}.csv"
    [ -f "$csv" ] && [ "$(wc -l < "$csv")" -ge 13 ]
}

is_running() {
    local y=$1
    pgrep -f "eemt_pinaleno_year.py --year ${y} " > /dev/null 2>&1
}

next_year() {
    local y
    for y in $(seq "$START_YEAR" "$END_YEAR"); do
        if ! is_done "$y" && ! is_running "$y"; then
            echo "$y"
            return 0
        fi
    done
    return 1
}

# Promote a finished year's monthly_stats.csv into the canonical stats slot.
# Idempotent. Lets us count "done" via a single file pattern.
promote_finished() {
    local y
    for y in $(seq "$START_YEAR" "$END_YEAR"); do
        local csv="${STATS_DIR}/stats_${y}.csv"
        local year_csv="${OUT}/${y}/monthly_stats.csv"
        if [ ! -f "$csv" ] && [ -f "$year_csv" ]; then
            cp "$year_csv" "$csv" && log "promoted ${y} monthly_stats.csv"
        fi
    done
}

launch_year() {
    local y=$1
    local log_file="${STATS_DIR}/log_${y}.txt"
    nohup python3 "$RUNNER" --year "$y" --per-year-output --keep-cache \
        > "$log_file" 2>&1 &
    log "launched year=${y} pid=$!"
}

# Main loop
while true; do
    promote_finished

    # All done?
    all_done=1
    for y in $(seq "$START_YEAR" "$END_YEAR"); do
        if ! is_done "$y"; then all_done=0; break; fi
    done
    if [ $all_done -eq 1 ]; then
        log "all years complete; dispatcher exiting"
        break
    fi

    own=$(pgrep -cf "eemt_pinaleno_year.py" || echo 0)
    load1=$(awk '{print $1}' /proc/loadavg)
    free_cores=$(awk -v c="$NCORES" -v l="$load1" 'BEGIN{printf "%d", c-l}')
    free_gb=$(awk '/MemAvailable/{printf "%d", $2/1024/1024}' /proc/meminfo)

    reason=""
    [ "$own" -ge "$MAX_OWN" ]            && reason="${reason}max_own "
    [ "$free_cores" -lt "$MIN_FREE_CORES" ] && reason="${reason}cores "
    [ "$free_gb" -lt "$MIN_FREE_GB" ]    && reason="${reason}ram "

    if [ -z "$reason" ]; then
        if y=$(next_year); then
            log "ok own=${own} free_cores=${free_cores} free_gb=${free_gb} -> launch ${y}"
            launch_year "$y"
        else
            log "ok own=${own} free_cores=${free_cores} free_gb=${free_gb} but no eligible year"
        fi
    else
        log "hold own=${own} free_cores=${free_cores} free_gb=${free_gb} reason=${reason}"
    fi

    sleep "$TICK"
done
