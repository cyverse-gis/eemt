# Pinaleño Mountains EEMT Project

Effective Energy & Mass Transfer modeling for the Pinaleño + Santa Teresa Mountains
(Graham County, southeast Arizona).

## Study Area

- **Bounding box (WGS84):** 32.50–33.15 N, -110.40 to -109.75 W
- **Area:** ~62 km × 73 km (UTM 12N: 6147 × 7259 px @ 10 m)
- **Elevation:** 785–3264 m (Mt Graham summit at 3267 m USGS, 3263 m in DEM)
- **Sub-ranges:**
  - Pinaleño Mountains (Mt Graham, Heliograph Peak, sky islands)
  - Santa Teresa Mountains (NW extension)

## Data Locations

| Asset | Path |
|---|---|
| 10m DEM (active) | `/opt/tswetnam/pinaleno/dem/pinaleno_dem_10m.tif` |
| 1m lidar DEM (staged, not yet downloaded) | `/opt/tswetnam/pinaleno/lidar_1m/` |
| DAYMET v4 R1 (1980–2024) | `/opt/tswetnam/pinaleno/daymet/daily/` |
| Solar (r.sun outputs) | `/opt/tswetnam/pinaleno/solar/10m/dem/` |
| EEMT outputs | `/opt/tswetnam/pinaleno/eemt/` |

## Why 10m and not 1m

`/opt/tswetnam` (the 21 TB volume used for SEAZ and Gordon Gulch) is 100% full.
1m lidar at full mountain-range extent would need ~100 GB of headroom.
The 1m download script is staged (`scripts/download_dem_1m_lidar.sh`)
and will run once disk space is freed.

## Pipeline Steps

1. `scripts/download_dem_10m.sh` — USGS 3DEP 1/3 arc-sec mosaic → UTM 12N COG ✓
2. `scripts/download_dem_1m_lidar.sh` — staged for future 1m run
3. `scripts/download_pinaleno_daymet.py` — DAYMET 1980–2024 via OPeNDAP
4. `scripts/run_pinaleno_solar.sh` — 365-day r.sun + 12 monthly aggregations
5. `scripts/run_pinaleno_eemt.sh` — EEMT analysis 1980–2024
