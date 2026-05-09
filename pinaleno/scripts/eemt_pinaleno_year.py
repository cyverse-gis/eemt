#!/usr/bin/env python3
"""Run EEMT streaming for one Pinaleño year.

Patches seaz_eemt_streaming with:
  - Multi-band gdalwarp (4 calls/year vs 1460): warp each NetCDF variable
    to a single multi-band UTM-10m TIF instead of 365 single-band TIFs.
  - Per-day reads use band index (read_raster(path, band=day_num)) — supported.
  - Cache deletion after the year writes its monthly outputs, so disk peak
    is ~133 GB and resets between years.

Usage: python3 eemt_pinaleno_year.py --year 1980 --per-year-output [--quiet]
"""

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, "/home/tswetnam/github/eemt/scripts")
import seaz_eemt_streaming as st

st.DEM_PATH = "/opt/tswetnam/pinaleno/dem/pinaleno_dem_10m.tif"
st.SOLAR_DIR = "/opt/tswetnam/pinaleno/solar/10m/dem"
st.DAYMET_DIR = "/opt/tswetnam/pinaleno/daymet/daily"
st.OUTPUT_DIR = "/opt/tswetnam/pinaleno/eemt"

DEM_PATH = st.DEM_PATH
SOLAR_DIR = st.SOLAR_DIR
DAYMET_DIR = st.DAYMET_DIR
OUTPUT_DIR = st.OUTPUT_DIR


def multiband_prewarp(year, dem_path, output_dir, quiet=False):
    cache_dir = os.path.join(output_dir, "inputs", "daymet_daily_warped")
    os.makedirs(cache_dir, exist_ok=True)

    dem_info = st.get_raster_info(dem_path)
    stdout, _, _ = st.run_cmd(["gdalsrsinfo", "-o", "proj4", dem_path])
    dem_crs = stdout.strip().strip("'\"") or "EPSG:32612"

    xmin = dem_info["xmin"]
    ymax = dem_info["ymax"]
    xmax = xmin + dem_info["cols"] * dem_info["xres"]
    ymin = ymax - dem_info["rows"] * dem_info["yres"]

    for var in ["tmin", "tmax", "prcp", "vp"]:
        out_path = os.path.join(cache_dir, f"{var}_{year}_multiband.tif")
        if os.path.isfile(out_path):
            info = st.get_raster_info(out_path)
            if info and info.get("nbands", 0) >= 365:
                if not quiet:
                    print(f"    {var} {year}: cached ({info['nbands']} bands)")
                continue

        nc_path = next(
            (str(p) for p in sorted(Path(DAYMET_DIR, var).glob(f"{var}_{year}_*.nc"))),
            None,
        )
        if not nc_path or not os.path.isfile(nc_path):
            raise FileNotFoundError(f"DAYMET missing: {var} {year}")

        sd = f"NETCDF:{nc_path}:{var}"
        cmd = [
            "gdalwarp", "-q", "-overwrite",
            "-t_srs", dem_crs,
            "-te", str(xmin), str(ymin), str(xmax), str(ymax),
            "-ts", str(dem_info["cols"]), str(dem_info["rows"]),
            "-r", "bilinear",
            "-co", "COMPRESS=LZW", "-co", "TILED=YES", "-co", "BIGTIFF=YES",
            "-co", "INTERLEAVE=BAND",
            "-multi", "-wo", "NUM_THREADS=ALL_CPUS",
            sd, out_path,
        ]
        t0 = time.time()
        _, err, rc = st.run_cmd(cmd, timeout=3600)
        if rc != 0:
            raise RuntimeError(f"gdalwarp {var} {year} failed: {err}")
        if not quiet:
            print(f"    {var}: multi-band warp ok ({time.time()-t0:.0f}s)", flush=True)

    return cache_dir


def compute_eemt_multiband(year, dem, dem_1km, valid, slope_rad, aspect_rad,
                           twi, dem_path, output_dir, quiet=False):
    rows, cols = dem.shape

    twi_valid = twi.copy()
    twi_valid[~valid] = np.nan
    twi_median = np.nanmedian(twi_valid)
    if twi_median == 0:
        twi_median = 1.0
    a_i = twi / twi_median
    del twi_valid

    N = np.cos(slope_rad) * np.cos(aspect_rad)
    g_psy = 1013.0 * (101.3 * ((293.0 - st.LAPSE_RATE * dem) / 293.0) ** 5.26)
    ra = (4.72 * (np.log(2.0 / 0.00137)) ** 2) / (1.0 + 0.536 * 5.0)
    NPP_topo = 0.39 * dem + 346.0 * N - 187.0
    E_bio_topo_const = NPP_topo * st.H_BIO / 1000.0

    monthly_accum = {m: {
        "EEMT_Trad": np.zeros((rows, cols), dtype=np.float64),
        "EEMT_Topo": np.zeros((rows, cols), dtype=np.float64),
        "NPP_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "E_ppt_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "E_bio_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "tmean_sum": np.zeros((rows, cols), dtype=np.float64),
        "ndays": 0,
    } for m in range(12)}

    day_to_month = []
    for mi, nd in enumerate(st.MONTH_DAYS):
        day_to_month.extend([mi] * nd)

    if not quiet:
        print("    Pre-computing monthly flat solar means...", flush=True)
    monthly_flat_sun = {}
    for month in st.MONTHS:
        sp = os.path.join(SOLAR_DIR, "global", "monthly", f"total_sun_{month}_sum.tif")
        total_sun_month = st.read_raster(sp)
        monthly_flat_sun[month] = np.mean(total_sun_month[valid])
        del total_sun_month

    if not quiet:
        print(f"    Pre-warping DAYMET {year} (multi-band)...", flush=True)
    cache_dir = multiband_prewarp(year, dem_path, output_dir, quiet=quiet)

    tmin_path = os.path.join(cache_dir, f"tmin_{year}_multiband.tif")
    tmax_path = os.path.join(cache_dir, f"tmax_{year}_multiband.tif")
    prcp_path = os.path.join(cache_dir, f"prcp_{year}_multiband.tif")

    ndays = 365
    if not quiet:
        print(f"    Processing {ndays} days (streaming, multi-band)...", flush=True)

    eps = st.eps
    last_pct = -1
    for d in range(ndays):
        mi = day_to_month[d]
        month_name = st.MONTHS[mi]
        day_num = d + 1

        sp = os.path.join(SOLAR_DIR, "global", "daily", f"total_sun_day_{day_num}.tif")
        ip = os.path.join(SOLAR_DIR, "insol", "daily", f"hours_sun_day_{day_num}.tif")
        total_sun = st.read_raster(sp)
        hours_sun = st.read_raster(ip)
        flat_sun_mean = monthly_flat_sun[month_name] / st.MONTH_DAYS[mi]

        tmin = st.read_raster(tmin_path, band=day_num)
        tmax = st.read_raster(tmax_path, band=day_num)
        prcp = st.read_raster(prcp_path, band=day_num)

        tmin_loc = tmin - st.LAPSE_RATE * (dem - dem_1km)
        tmax_loc = tmax - st.LAPSE_RATE * (dem - dem_1km)
        tmean_loc = (tmax_loc + tmin_loc) / 2.0

        es_tmin = np.where(tmin_loc > 0,
                           0.6108 * np.exp(17.27 * tmin_loc / (tmin_loc + 237.3)), 0)
        es_tmax = np.where(tmax_loc > 0,
                           0.6108 * np.exp(17.27 * tmax_loc / (tmax_loc + 237.3)), 0)
        e_s = np.where(tmean_loc > 0, (es_tmax + es_tmin) / 2.0, 0)
        PET_Trad = np.where(e_s > 0,
                            (29.8 * hours_sun * e_s) / (tmean_loc + 273.2), 0)

        S_i = np.where(flat_sun_mean > eps, total_sun / flat_sun_mean, 1.0)
        S_i = np.clip(S_i, 0.01, 100.0)
        tmax_topo = tmax_loc + (S_i - 1.0 / S_i)
        tmean_topo = (tmax_loc + tmin_loc) / 2.0 + (S_i - 1.0 / S_i) / 2.0

        m_vp = 0.04145 * np.exp(0.06088 * tmean_topo)
        vp_loc = 6.11 * (10.0 ** (7.5 * tmin_loc / (237.3 + tmin_loc + eps)))

        prcp_safe = np.maximum(prcp, eps)
        pet_ratio = np.where(prcp > 0, np.where(tmean_topo > 0, 1.0, 0) / prcp_safe, 0)
        AET_zb = np.where(tmean_topo > 0,
                          prcp * (1.0 + pet_ratio - (1.0 + pet_ratio ** 2.63) ** (1.0 / 2.63)),
                          0)
        P_eff = prcp - AET_zb
        F = np.where(prcp > 0, a_i * P_eff, 0)

        E_ppt_trad = np.where((prcp > 0) & (tmean_loc > 0),
                              np.maximum(0, prcp - PET_Trad * 10.0) * st.C_WATER * tmean_loc, 0)
        NPP_trad = np.where(tmean_loc > 0,
                            st.NPP_MAX / (1.0 + np.exp(1.315 - 0.119 * tmean_loc)), 0)
        E_bio_trad = np.where(tmean_loc > 0, NPP_trad * st.H_BIO / 1000.0 / 365.0, 0)
        EEMT_Trad = (E_ppt_trad + E_bio_trad) / 1e6

        E_ppt_topo = np.where((prcp > 0) & (tmean_topo > 0),
                              F * st.C_WATER * tmean_topo, 0)
        EEMT_Topo = (E_ppt_topo + E_bio_topo_const / 365.0) / 1e6

        EEMT_Trad[~valid] = 0
        EEMT_Topo[~valid] = 0
        NPP_trad[~valid] = 0
        E_ppt_trad[~valid] = 0
        E_bio_trad[~valid] = 0
        tmean_loc[~valid] = 0

        acc = monthly_accum[mi]
        acc["EEMT_Trad"] += EEMT_Trad
        acc["EEMT_Topo"] += EEMT_Topo
        acc["NPP_trad_sum"] += NPP_trad
        acc["E_ppt_trad_sum"] += E_ppt_trad
        acc["E_bio_trad_sum"] += E_bio_trad
        acc["tmean_sum"] += tmean_loc
        acc["ndays"] += 1

        pct = int((d + 1) / ndays * 100)
        if pct % 10 == 0 and pct != last_pct:
            if not quiet:
                print(f"      {pct}% ({d+1}/{ndays} days)", flush=True)
            last_pct = pct

    monthly_results = []
    for mi in range(12):
        acc = monthly_accum[mi]
        nd = max(acc["ndays"], 1)

        eemt_trad = acc["EEMT_Trad"].astype(np.float32)
        eemt_topo = acc["EEMT_Topo"].astype(np.float32)
        npp_mean = (acc["NPP_trad_sum"] / nd).astype(np.float32)
        tmean_mean = (acc["tmean_sum"] / nd).astype(np.float32)

        eemt_trad[~valid] = st.NODATA
        eemt_topo[~valid] = st.NODATA
        npp_mean[~valid] = st.NODATA
        tmean_mean[~valid] = st.NODATA

        eemt_dir = os.path.join(output_dir, "eemt")
        os.makedirs(eemt_dir, exist_ok=True)
        for key, arr in [("EEMT_Trad", eemt_trad), ("EEMT_Topo", eemt_topo)]:
            out_path = os.path.join(eemt_dir, f"{key}_{st.MONTHS[mi]}_{year}.tif")
            st.write_raster(arr, out_path, dem_path)

        monthly_results.append({
            "EEMT_Trad": eemt_trad, "EEMT_Topo": eemt_topo,
            "NPP_trad": npp_mean,
            "E_ppt_trad": (acc["E_ppt_trad_sum"] / 1e6).astype(np.float32),
            "E_bio_trad": (acc["E_bio_trad_sum"] / 1e6).astype(np.float32),
            "E_ppt_topo": np.zeros_like(eemt_trad),
            "E_bio_topo": np.zeros_like(eemt_trad),
            "tmean_loc": tmean_mean, "tmean_topo": tmean_mean,
        })

        trad_v = eemt_trad[valid]
        if not quiet:
            print(f"  {st.MONTHS[mi]}: EEMT_Trad mean={np.mean(trad_v):>8.2f}, "
                  f"range=[{np.min(trad_v):.2f}, {np.max(trad_v):.2f}] MJ/m2, "
                  f"tmean={np.mean(tmean_mean[valid]):.1f}C ({nd} days)", flush=True)

    return monthly_results


def main():
    parser = argparse.ArgumentParser(description="EEMT streaming — Pinaleño multi-band")
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--per-year-output", action="store_true")
    parser.add_argument("--quiet", "-q", action="store_true")
    parser.add_argument("--keep-cache", action="store_true",
                        help="Don't delete daymet_daily_warped after the run")
    args = parser.parse_args()
    year = args.year

    output_dir = OUTPUT_DIR
    if args.per_year_output:
        output_dir = os.path.join(OUTPUT_DIR, str(year))

    if not args.quiet:
        print(f"EEMT — Pinaleño {year}")
        print("=" * 60, flush=True)

    t0 = time.time()
    os.makedirs(os.path.join(output_dir, "inputs"), exist_ok=True)
    os.makedirs(os.path.join(output_dir, "eemt"), exist_ok=True)

    if not args.quiet:
        print("\n[Phase 1] Loading inputs...", flush=True)
    dem = st.read_raster(DEM_PATH)
    valid = dem > 0
    if not args.quiet:
        print(f"  DEM: {dem.shape[1]}x{dem.shape[0]}, "
              f"elevation {np.min(dem[valid]):.0f}-{np.max(dem[valid]):.0f} m", flush=True)

    shared = OUTPUT_DIR
    slope_rad = st.read_raster(os.path.join(shared, "inputs", "slope_rad.tif"))
    aspect_rad = st.read_raster(os.path.join(shared, "inputs", "aspect_rad.tif"))
    twi = st.read_raster(os.path.join(shared, "inputs", "twi.tif"))
    dem_1km = st.read_raster(os.path.join(shared, "inputs", "dem_1km.tif"))

    if not args.quiet:
        print(f"\n[Phase 2] Computing EEMT for {year}...", flush=True)
    monthly_results = compute_eemt_multiband(
        year, dem, dem_1km, valid, slope_rad, aspect_rad, twi,
        DEM_PATH, output_dir, quiet=args.quiet,
    )

    if not args.quiet:
        print("\n[Phase 3] Writing stats CSV...", flush=True)
    csv_path = st.generate_stats(monthly_results, valid, year, output_dir)

    annual_trad = np.zeros_like(monthly_results[0]["EEMT_Trad"])
    for mr in monthly_results:
        et = mr["EEMT_Trad"].copy()
        et[~valid] = 0
        annual_trad += et
    annual_v = annual_trad[valid]
    elapsed = time.time() - t0

    print(f"{year}: EEMT mean={np.mean(annual_v):.1f} MJ/m2/yr, "
          f"range=[{np.min(annual_v):.1f}, {np.max(annual_v):.1f}], "
          f"elapsed={elapsed:.0f}s", flush=True)

    if not args.keep_cache:
        cache_dir = os.path.join(output_dir, "inputs", "daymet_daily_warped")
        if os.path.isdir(cache_dir):
            shutil.rmtree(cache_dir, ignore_errors=True)
            if not args.quiet:
                print("  cache deleted", flush=True)


if __name__ == "__main__":
    main()
