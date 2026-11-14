---
title: Gordon Gulch EEMT Analysis (1980-2024)
description: 45-year EEMT analysis of the Gordon Gulch Critical Zone site with Lean 4 formal verification
---

# Gordon Gulch EEMT Analysis (1980-2024)

## Study Area

Gordon Gulch is a 2.6 km² headwater catchment in the Boulder Creek Critical Zone Observatory (CZO), located in the Arapaho-Roosevelt National Forest, Colorado (~40.02°N, 105.47°W). The analysis was performed at two spatial extents:

| Parameter | Original | Expanded |
|-----------|----------|----------|
| Extent | 4.3 × 3.0 km | 16 × 9 km |
| Grid | 434 × 296 px | 1,606 × 891 px |
| Elevation | 2,377 – 2,792 m | 1,942 – 3,523 m |
| Resolution | 10 m (USGS 3DEP) | 10 m (USGS 3DEP) |

## Data Sources

| Data | Source | Temporal Coverage |
|------|--------|-------------------|
| DEM | USGS 3DEP 1/3 arc-second (tiles n40w106 + n41w106) | Static |
| Solar radiation | GPU-accelerated r.sun (NVIDIA A100, `rsun` Rust binary) | 365 days/yr |
| Climate | DAYMET V4 R1 via OPeNDAP (NASA Earthdata) | 1980–2024 daily |
| Validation | Lean 4 formal verification (60+ equations) | Static |

### DAYMET Access

DAYMET data is accessed via OPeNDAP from NASA Earthdata:

```
https://opendap.earthdata.nasa.gov/collections/C2532426483-ORNL_CLOUD/granules/
  Daymet_Daily_V4R1.daymet_v4_daily_na_{var}_{year}.nc
```

Requires `~/.netrc` with Earthdata Login credentials. Spatial subsetting via OPeNDAP constraint expressions (e.g., `tmin[0:364][5227:5240][4104:4123]`).

## Methods

### Computation Pipeline

1. **Solar radiation**: 365 daily r.sun computations on the A100 GPU (32–58 seconds for 1.4M pixels)
2. **DAYMET processing**: Daily NetCDF bands warped from LCC (1 km) to UTM 13N (10 m) via `gdalwarp`
3. **EEMT calculation**: Daily-resolution computation following Rasmussen et al. (2005, 2011, 2015), summed to monthly totals
4. **Validation**: 8 Lean 4 formally verified checks per year

### Bug Fixes (Identified via Lean 4 Verification)

Three critical bugs in `eemt/eemt/reemt.sh` were identified and fixed:

| Line | Bug | Impact |
|------|-----|--------|
| 174 | `f_tmax_topo` used `tmin_topo` (copy-paste error) | Systematic PET underestimation |
| 197 | `E_ppt_trad` missing ΔT temperature term | E_PPT ~2× too low |
| 215 | `E_ppt_topo` included spurious `E_bio_topo` multiplier | Dimensional nonsense (J²/m²) |

## Results

### Annual EEMT Summary (1980–2024)

| Statistic | Original (4.3×3 km) | Expanded (16×9 km) |
|-----------|---------------------|---------------------|
| Mean | 21.3 ± 1.9 MJ/m²/yr | 21.8 ± 1.9 MJ/m²/yr |
| Range | 17.4 – 27.7 | 17.8 – 27.8 |
| Trend | +0.099/yr (R²=0.47) | +0.101/yr (R²=0.54) |
| Total change | +4.4 MJ/m²/yr | +4.5 MJ/m²/yr |
| Regime | 100% water-limited | 100% water-limited |

### Decadal Trends

| Decade | Mean EEMT | Std | Change |
|--------|-----------|-----|--------|
| 1980s | 19.8 | 1.2 | — |
| 1990s | 20.8 | 0.9 | +1.0 |
| 2000s | 22.3 | 0.7 | +1.5 |
| 2010s | 23.6 | 1.6 | +1.2 |
| 2020s | 22.7 | 0.3 | -0.8 |

### Extreme Years

**Highest EEMT:**

1. 2013 — 27.8 MJ/m²/yr (Neutral, warmest year)
2. 2012 — 25.7 MJ/m²/yr (La Nina, record drought + heat)
3. 2017 — 24.4 MJ/m²/yr (Neutral)

**Lowest EEMT:**

1. 1984 — 17.7 MJ/m²/yr (La Nina, cold early 1980s)
2. 1985 — 18.3 MJ/m²/yr (La Nina)
3. 1982 — 18.6 MJ/m²/yr (Neutral)

### ENSO Analysis

No statistically significant difference between ENSO phases:

| Comparison | t-statistic | p-value | Significance |
|-----------|-------------|---------|--------------|
| El Nino vs Neutral | 0.59 | 0.56 | ns |
| La Nina vs Neutral | 0.50 | 0.62 | ns |
| El Nino vs La Nina | 0.05 | 0.96 | ns |
| Strong El Nino vs Neutral | -0.22 | 0.82 | ns |
| Strong La Nina vs Neutral | 0.44 | 0.66 | ns |

ENSO's influence on Colorado Front Range precipitation and temperature is weak compared to Pacific Northwest or Southwest sites.

### Lean 4 Validation

All 8 formally verified checks pass across all 45 years:

| Theorem | Description | Status |
|---------|-------------|--------|
| `eemt_nonneg` | EEMT ≥ 0 for all valid pixels | PASS |
| `nppTemp_lt_max` | NPP < 3,000 g/m²/yr | PASS |
| `ePpt_zero_frozen` | E_PPT = 0 when T ≤ 0°C | PASS |
| `validEEMTRange` | Annual EEMT ∈ [0.1, 500] MJ/m²/yr | PASS |
| `regime_partition` | Water/energy limited classification | PASS |
| `eemt_monotone_temp` | EEMT increases with temperature | PASS |
| `nppTemp_strictMono` | NPP increases with temperature | PASS |
| `eemt_decomposition` | EEMT = E_BIO + E_PPT | PASS |

## Outputs

### CyVerse Data Store

Results are available at:

```
/iplant/home/tswetnam/eemt/gordon_gulch/
  eemt/
    eemt_smoke_test/    # Original extent (4.3×3 km)
    eemt_16km/          # Expanded extent (16×9 km)
      {1980-2024}/      # Per-year directories
        eemt/EEMT_Trad_{month}_{year}.tif
        eemt/EEMT_Topo_{month}_{year}.tif
        monthly_stats.csv
      eemt_zscore_1980_2024.gif   # Z-score animation (magma)
      eemt_zscore_1980_2024.mp4
      multiyear_summary_report.txt
      multiyear_annual_stats.csv
  notebooks/
    gordon_gulch_eemt_report.ipynb  # Interactive report (8 figures)
```

### Jupyter Notebook

The comprehensive report notebook (`gordon_gulch_eemt_report.ipynb`) contains 8 publication-quality figures:

1. DEM hillshade visualization
2. Annual EEMT time series with ENSO markers and trend
3. Monthly z-score heatmap (year × month)
4. ENSO phase analysis (box plots, seasonal curves, anomaly bars)
5. Climate driver scatter matrix
6. Seasonal cycle with uncertainty bands
7. Lean 4 NPP verification + validation table
8. Spatial extent comparison (1:1 scatter)

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/test_daymet_access.py` | DAYMET API validation and download |
| `scripts/eemt_smoke_test.py` | Standalone EEMT computation (`--daily` mode) |
| `scripts/eemt_multiyear_report.py` | Multi-year summary with ENSO analysis |
| `scripts/eemt_zscore_animation.py` | Z-score GIF/MP4 animation |
| `scripts/run_all_years.sh` | Parallel batch runner |
| `scripts/run_16km_eemt.sh` | 16km extent batch runner |

## Reproducibility

```bash
# 1. Download DAYMET data
python3 scripts/test_daymet_access.py --year 2020

# 2. Run solar radiation (requires rsun binary + GPU)
rsun compute --dem dem.tif --day 1-365 --step 15 --output-dir output/

# 3. Run single-year EEMT (daily mode)
python3 scripts/eemt_smoke_test.py --year 2020 --daily

# 4. Run all years in parallel
bash scripts/run_all_years.sh 31

# 5. Generate summary report
python3 scripts/eemt_multiyear_report.py

# 6. Generate z-score animation
python3 scripts/eemt_zscore_animation.py
```

## References

- Rasmussen, C., et al. (2005). Quantitative measures of landscape evolution. *Geology*, 33(7), 561–564.
- Rasmussen, C., & Tabor, N.J. (2007). Applying a quantitative pedogenic energy model. *SSSAJ*, 71(5), 1719–1729.
- Rasmussen, C., et al. (2015). Using EEMT as a proxy for soil production. *Vadose Zone Journal*, 14(7).
- Lieth, H. (1975). Modeling the primary productivity of the world. *Primary Productivity of the Biosphere*, 237–263.
- Thornton, P.E., et al. (2022). Daymet V4 R1. ORNL DAAC. doi:10.3334/ORNLDAAC/2129.
