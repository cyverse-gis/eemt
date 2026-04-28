#!/usr/bin/env python3
"""
EEMT Streaming Computation — SE Arizona
========================================
Memory-efficient EEMT computation for large DEMs.
Processes one day at a time instead of loading all DAYMET bands into memory.

Usage:
    python3 scripts/seaz_eemt_streaming.py --year 2020
    python3 scripts/seaz_eemt_streaming.py --year 2020 --quiet
"""

import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

# =============================================================================
# Configuration
# =============================================================================

DEM_PATH = "/opt/tswetnam/data/seaz/seaz_dem_10m.tif"
SOLAR_DIR = "/opt/tswetnam/data/seaz/10m/dem"
DAYMET_DIR = "/opt/tswetnam/data/seaz/daymet/daily"
OUTPUT_DIR = "/opt/tswetnam/data/seaz/eemt"

DAYMET_LCC = (
    "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 "
    "+x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
)

MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
          "jul", "aug", "sep", "oct", "nov", "dec"]
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

NODATA = -9999.0
CELL_AREA = 100.0  # 10m x 10m

# Lean 4 verified constants
LAPSE_RATE = 0.00649
NPP_MAX = 3000.0
H_BIO = 22e6
C_WATER = 4185.5

eps = 1e-10


# =============================================================================
# Raster I/O
# =============================================================================

def run_cmd(cmd, timeout=120):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout, r.stderr, r.returncode


def get_raster_info(path):
    stdout, _, rc = run_cmd(["gdalinfo", "-json", path])
    if rc != 0:
        return None
    info = json.loads(stdout)
    size = info.get("size", [0, 0])
    gt = info.get("geoTransform", [0, 1, 0, 0, 0, -1])
    nodata = None
    bands = info.get("bands", [])
    if bands:
        nodata = bands[0].get("noDataValue")
    return {
        "cols": size[0], "rows": size[1],
        "gt": gt, "nodata": nodata,
        "nbands": len(bands),
        "xmin": gt[0], "xres": gt[1],
        "ymax": gt[3], "yres": abs(gt[5]),
    }


def read_raster(path, band=None):
    info = get_raster_info(path)
    if info is None:
        raise FileNotFoundError(f"Cannot read: {path}")
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        cmd = ["gdal_translate", "-of", "ENVI", "-ot", "Float32", "-q"]
        if band is not None:
            cmd += ["-b", str(band)]
        cmd += [path, tmp_path]
        _, err, rc = run_cmd(cmd, timeout=300)
        if rc != 0:
            raise RuntimeError(f"gdal_translate failed: {err}")
        data = np.fromfile(tmp_path, dtype=np.float32)
        if band is not None:
            data = data.reshape(info["rows"], info["cols"])
        else:
            nbands = info["nbands"]
            if nbands > 1:
                data = data.reshape(nbands, info["rows"], info["cols"])
            else:
                data = data.reshape(info["rows"], info["cols"])
        return data
    finally:
        for ext in ["", ".hdr", ".aux.xml"]:
            p = tmp_path + ext if ext else tmp_path
            if os.path.exists(p):
                os.remove(p)


def write_raster(array, path, ref_tif):
    info = get_raster_info(ref_tif)
    rows, cols = array.shape
    gt = info["gt"]
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp:
        tmp_path = tmp.name
    hdr_path = tmp_path + ".hdr"
    try:
        array.astype(np.float32).tofile(tmp_path)
        with open(hdr_path, "w") as f:
            f.write("ENVI\n")
            f.write(f"samples = {cols}\nlines = {rows}\n")
            f.write("bands = 1\nheader offset = 0\ndata type = 4\n")
            f.write("interleave = bsq\nbyte order = 0\n")
        xmin = gt[0]
        ymax = gt[3]
        xmax = xmin + cols * gt[1]
        ymin = ymax + rows * gt[5]
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        srs_stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", ref_tif])
        proj4 = srs_stdout.strip().strip("'\"") or "EPSG:32612"
        cmd = [
            "gdal_translate", "-of", "GTiff", "-q",
            "-a_ullr", str(xmin), str(ymax), str(xmax), str(ymin),
            "-a_srs", proj4, "-a_nodata", str(NODATA),
            "-co", "COMPRESS=LZW", tmp_path, path,
        ]
        _, err, rc = run_cmd(cmd)
        if rc != 0:
            raise RuntimeError(f"write_raster failed: {err}")
    finally:
        for p in [tmp_path, hdr_path, tmp_path + ".aux.xml"]:
            if os.path.exists(p):
                os.remove(p)


# =============================================================================
# DAYMET: warp single band on-the-fly
# =============================================================================

def warp_daymet_band(nc_data_2d, nc_gt, dem_info, dem_crs, tmp_dir):
    """Warp a single DAYMET band from LCC to DEM grid."""
    r, c = nc_data_2d.shape
    tmp_bin = os.path.join(tmp_dir, "band.bin")
    tmp_hdr = tmp_bin + ".hdr"
    tmp_lcc = os.path.join(tmp_dir, "band_lcc.tif")
    tmp_utm = os.path.join(tmp_dir, "band_utm.tif")

    nc_data_2d.astype(np.float32).tofile(tmp_bin)
    with open(tmp_hdr, "w") as f:
        f.write(f"ENVI\nsamples = {c}\nlines = {r}\n")
        f.write("bands = 1\nheader offset = 0\ndata type = 4\n")
        f.write("interleave = bsq\nbyte order = 0\n")

    nc_xmin = nc_gt[0]
    nc_ymax = nc_gt[3]
    nc_xmax = nc_xmin + c * nc_gt[1]
    nc_ymin = nc_ymax + r * nc_gt[5]

    run_cmd([
        "gdal_translate", "-of", "GTiff", "-q",
        "-a_ullr", str(nc_xmin), str(nc_ymax), str(nc_xmax), str(nc_ymin),
        "-a_srs", DAYMET_LCC, tmp_bin, tmp_lcc,
    ])

    xmin = dem_info["xmin"]
    ymax = dem_info["ymax"]
    xmax = xmin + dem_info["cols"] * dem_info["xres"]
    ymin = ymax - dem_info["rows"] * dem_info["yres"]

    run_cmd([
        "gdalwarp", "-q", "-overwrite",
        "-s_srs", DAYMET_LCC, "-t_srs", dem_crs,
        "-te", str(xmin), str(ymin), str(xmax), str(ymax),
        "-ts", str(dem_info["cols"]), str(dem_info["rows"]),
        "-r", "bilinear", tmp_lcc, tmp_utm,
    ])

    result = read_raster(tmp_utm)
    for p in [tmp_bin, tmp_hdr, tmp_bin + ".aux.xml", tmp_lcc, tmp_utm]:
        if os.path.exists(p):
            os.remove(p)
    return result


# =============================================================================
# Pre-warp all DAYMET bands to cached GeoTIFFs (one-time per year)
# =============================================================================

def prewarp_daymet_year(year, dem_path, output_dir):
    """Warp all 365 DAYMET bands to DEM grid, cache as GeoTIFFs.

    This is slow the first time but avoids repeated warping and
    allows streaming one day at a time during EEMT computation.
    """
    cache_dir = os.path.join(output_dir, "inputs", "daymet_daily_warped")
    os.makedirs(cache_dir, exist_ok=True)

    # Check if already cached
    test_file = os.path.join(cache_dir, f"tmin_{year}_day_001.tif")
    if os.path.isfile(test_file):
        print(f"    DAYMET {year} already warped (cached)")
        return cache_dir

    dem_info = get_raster_info(dem_path)
    stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", dem_path])
    dem_crs = stdout.strip().strip("'\"")
    tmp_dir = tempfile.mkdtemp(prefix="daymet_warp_")

    for var in ["tmin", "tmax", "prcp", "vp"]:
        nc_path = next(
            (str(p) for p in sorted(Path(DAYMET_DIR, var).glob(f"{var}_{year}_*.nc"))),
            os.path.join(DAYMET_DIR, var, f"{var}_{year}_seaz.nc"),
        )
        if not os.path.isfile(nc_path):
            print(f"    [-] Missing: {nc_path}")
            continue

        sd = f"NETCDF:{nc_path}:{var}"
        sd_info = get_raster_info(sd)
        if sd_info is None:
            print(f"    [-] Cannot read: {sd}")
            continue

        all_bands = read_raster(sd)
        if all_bands.ndim == 2:
            all_bands = all_bands[np.newaxis, :, :]
        nc_gt = sd_info["gt"]
        ndays = all_bands.shape[0]

        for d in range(ndays):
            out_path = os.path.join(cache_dir, f"{var}_{year}_day_{d+1:03d}.tif")
            if os.path.isfile(out_path):
                continue
            warped = warp_daymet_band(all_bands[d], nc_gt, dem_info, dem_crs, tmp_dir)
            write_raster(warped, out_path, dem_path)
            del warped

        print(f"    {var}: {ndays} days warped")
        del all_bands

    try:
        os.rmdir(tmp_dir)
    except OSError:
        pass

    return cache_dir


# =============================================================================
# Streaming EEMT: process one day at a time
# =============================================================================

def compute_eemt_streaming(year, dem, dem_1km, valid, slope_rad, aspect_rad,
                          twi, dem_path, output_dir, quiet=False):
    """Compute EEMT day-by-day, accumulating to monthly totals.

    Only 5 rasters in memory per day iteration (~2.4 GB for 80M pixels).
    """
    rows, cols = dem.shape

    # TWI constants (invariant)
    twi_valid = twi.copy()
    twi_valid[~valid] = np.nan
    twi_median = np.nanmedian(twi_valid)
    if twi_median == 0:
        twi_median = 1.0
    a_i = twi / twi_median
    del twi_valid

    # Northness (invariant)
    N = np.cos(slope_rad) * np.cos(aspect_rad)

    # Elevation-dependent constants
    g_psy = 1013.0 * (101.3 * ((293.0 - LAPSE_RATE * dem) / 293.0) ** 5.26)
    ra = (4.72 * (np.log(2.0 / 0.00137)) ** 2) / (1.0 + 0.536 * 5.0)

    # NPP_topo (invariant)
    NPP_topo = 0.39 * dem + 346.0 * N - 187.0
    E_bio_topo_const = NPP_topo * H_BIO / 1000.0

    # Monthly accumulators
    monthly_accum = {m: {
        "EEMT_Trad": np.zeros((rows, cols), dtype=np.float64),
        "EEMT_Topo": np.zeros((rows, cols), dtype=np.float64),
        "NPP_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "E_ppt_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "E_bio_trad_sum": np.zeros((rows, cols), dtype=np.float64),
        "tmean_sum": np.zeros((rows, cols), dtype=np.float64),
        "ndays": 0,
    } for m in range(12)}

    # Day-to-month mapping
    day_to_month = []
    for mi, nd in enumerate(MONTH_DAYS):
        day_to_month.extend([mi] * nd)

    # Pre-compute monthly flat_sun means
    if not quiet:
        print("    Pre-computing monthly flat solar means...")
    monthly_flat_sun = {}
    for month in MONTHS:
        sp = os.path.join(SOLAR_DIR, "global", "monthly", f"total_sun_{month}_sum.tif")
        total_sun_month = read_raster(sp)
        monthly_flat_sun[month] = np.mean(total_sun_month[valid])
        del total_sun_month

    # Pre-warp DAYMET to cached GeoTIFFs
    if not quiet:
        print(f"    Pre-warping DAYMET {year} to DEM grid...")
    cache_dir = prewarp_daymet_year(year, dem_path, output_dir)

    ndays = 365
    if not quiet:
        print(f"    Processing {ndays} days (streaming)...")

    last_pct = -1
    for d in range(ndays):
        mi = day_to_month[d]
        month_name = MONTHS[mi]
        day_num = d + 1

        # Read daily solar (stream from disk)
        sp = os.path.join(SOLAR_DIR, "global", "daily", f"total_sun_day_{day_num}.tif")
        ip = os.path.join(SOLAR_DIR, "insol", "daily", f"hours_sun_day_{day_num}.tif")
        total_sun = read_raster(sp)
        hours_sun = read_raster(ip)
        flat_sun_mean = monthly_flat_sun[month_name] / MONTH_DAYS[mi]

        # Read warped DAYMET for this day
        tmin = read_raster(os.path.join(cache_dir, f"tmin_{year}_day_{day_num:03d}.tif"))
        tmax = read_raster(os.path.join(cache_dir, f"tmax_{year}_day_{day_num:03d}.tif"))
        prcp = read_raster(os.path.join(cache_dir, f"prcp_{year}_day_{day_num:03d}.tif"))

        # --- Temperature lapse rate correction ---
        tmin_loc = tmin - LAPSE_RATE * (dem - dem_1km)
        tmax_loc = tmax - LAPSE_RATE * (dem - dem_1km)
        tmean_loc = (tmax_loc + tmin_loc) / 2.0

        # --- Hamon PET (Traditional) ---
        es_tmin = np.where(tmin_loc > 0,
                           0.6108 * np.exp(17.27 * tmin_loc / (tmin_loc + 237.3)), 0)
        es_tmax = np.where(tmax_loc > 0,
                           0.6108 * np.exp(17.27 * tmax_loc / (tmax_loc + 237.3)), 0)
        e_s = np.where(tmean_loc > 0, (es_tmax + es_tmin) / 2.0, 0)
        PET_Trad = np.where(e_s > 0,
                            (29.8 * hours_sun * e_s) / (tmean_loc + 273.2), 0)

        # --- Topographic temperature ---
        S_i = np.where(flat_sun_mean > eps, total_sun / flat_sun_mean, 1.0)
        S_i = np.clip(S_i, 0.01, 100.0)
        tmax_topo = tmax_loc + (S_i - 1.0 / S_i)
        tmean_topo = (tmax_loc + tmin_loc) / 2.0 + (S_i - 1.0 / S_i) / 2.0

        # --- Penman-Monteith PET (Topo) ---
        m_vp = 0.04145 * np.exp(0.06088 * tmean_topo)
        vp_loc = 6.11 * (10.0 ** (7.5 * tmin_loc / (237.3 + tmin_loc + eps)))
        f_tmin = np.where(tmin_loc > 0,
                          6.108 * np.exp(17.27 * tmin_loc / (tmin_loc + 237.3)), 0)
        f_tmax = np.where(tmax_topo > 0,
                          6.108 * np.exp(17.27 * tmax_topo / (tmax_topo + 237.3)), 0)
        vp_s = np.where(tmean_topo > 0, (f_tmax + f_tmin) / 2.0, 0)
        tmean_topo_safe = np.where(np.abs(tmean_topo) < eps, eps, tmean_topo)
        p_a = (101325.0 * np.exp(-9.80665 * 0.289644 * dem / (8.31447 * 288.15))
               / (287.35 * tmean_topo_safe * 273.125))
        total_sun_j = total_sun * 3600.0
        denom_pm = 2450000.0 * (m_vp + g_psy)
        denom_pm = np.where(np.abs(denom_pm) < eps, eps, denom_pm)
        PET_topo = np.where(tmean_topo > 0,
                            (m_vp * total_sun_j + p_a * 1013.0 * ((vp_s - vp_loc) / ra))
                            / denom_pm, 0)

        # --- Budyko AET + TWI ---
        prcp_safe = np.maximum(prcp, eps)
        pet_ratio = np.where(prcp > 0, PET_topo / prcp_safe, 0)
        AET_zb = np.where(tmean_topo > 0,
                          prcp * (1.0 + pet_ratio - (1.0 + pet_ratio ** 2.63) ** (1.0 / 2.63)),
                          0)
        P_eff = prcp - AET_zb
        F = np.where(prcp > 0, a_i * P_eff, 0)

        # --- EEMT-Traditional (daily) ---
        E_ppt_trad = np.where((prcp > 0) & (tmean_loc > 0),
                              np.maximum(0, prcp - PET_Trad * 10.0) * C_WATER * tmean_loc, 0)
        NPP_trad = np.where(tmean_loc > 0,
                            NPP_MAX / (1.0 + np.exp(1.315 - 0.119 * tmean_loc)), 0)
        E_bio_trad = np.where(tmean_loc > 0, NPP_trad * H_BIO / 1000.0 / 365.0, 0)
        EEMT_Trad = (E_ppt_trad + E_bio_trad) / 1e6

        # --- EEMT-Topographic (daily) ---
        E_ppt_topo = np.where((prcp > 0) & (tmean_topo > 0),
                              F * C_WATER * tmean_topo, 0)
        EEMT_Topo = (E_ppt_topo + E_bio_topo_const / 365.0) / 1e6

        # Mask and accumulate
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

    # Convert accumulators to monthly results and write GeoTIFFs
    monthly_results = []
    for mi in range(12):
        acc = monthly_accum[mi]
        nd = max(acc["ndays"], 1)

        eemt_trad = acc["EEMT_Trad"].astype(np.float32)
        eemt_topo = acc["EEMT_Topo"].astype(np.float32)
        npp_mean = (acc["NPP_trad_sum"] / nd).astype(np.float32)
        tmean_mean = (acc["tmean_sum"] / nd).astype(np.float32)

        eemt_trad[~valid] = NODATA
        eemt_topo[~valid] = NODATA
        npp_mean[~valid] = NODATA
        tmean_mean[~valid] = NODATA

        eemt_dir = os.path.join(output_dir, "eemt")
        os.makedirs(eemt_dir, exist_ok=True)
        for key, arr in [("EEMT_Trad", eemt_trad), ("EEMT_Topo", eemt_topo)]:
            out_path = os.path.join(eemt_dir, f"{key}_{MONTHS[mi]}_{year}.tif")
            write_raster(arr, out_path, dem_path)

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
            print(f"  {MONTHS[mi]}: EEMT_Trad mean={np.mean(trad_v):>8.2f}, "
                  f"range=[{np.min(trad_v):.2f}, {np.max(trad_v):.2f}] MJ/m2, "
                  f"tmean={np.mean(tmean_mean[valid]):.1f}C ({nd} days)", flush=True)

    return monthly_results


# =============================================================================
# Report generation
# =============================================================================

def generate_stats(monthly_results, valid, year, output_dir):
    """Generate monthly stats CSV."""
    csv_path = os.path.join(output_dir, "monthly_stats.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["month", "tmean_loc", "tmean_topo",
                        "eemt_trad_min", "eemt_trad_max", "eemt_trad_mean", "eemt_trad_std",
                        "eemt_topo_min", "eemt_topo_max", "eemt_topo_mean", "eemt_topo_std",
                        "npp_trad_mean", "e_ppt_trad_mean", "e_bio_trad_mean"])
        for i, mr in enumerate(monthly_results):
            trad_v = mr["EEMT_Trad"][valid]
            topo_v = mr["EEMT_Topo"][valid]
            writer.writerow([
                MONTHS[i],
                f"{np.mean(mr['tmean_loc'][valid]):.2f}",
                f"{np.mean(mr['tmean_topo'][valid]):.2f}",
                f"{np.min(trad_v):.2f}", f"{np.max(trad_v):.2f}",
                f"{np.mean(trad_v):.2f}", f"{np.std(trad_v):.2f}",
                f"{np.min(topo_v):.2f}", f"{np.max(topo_v):.2f}",
                f"{np.mean(topo_v):.2f}", f"{np.std(topo_v):.2f}",
                f"{np.mean(mr['NPP_trad'][valid]):.1f}",
                f"{np.mean(mr['E_ppt_trad'][valid]):.0f}",
                f"{np.mean(mr['E_bio_trad'][valid]):.0f}",
            ])
    return csv_path


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="EEMT Streaming — SE Arizona")
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--per-year-output", action="store_true")
    parser.add_argument("--quiet", "-q", action="store_true")
    args = parser.parse_args()
    year = args.year

    output_dir = OUTPUT_DIR
    if args.per_year_output:
        output_dir = os.path.join(OUTPUT_DIR, str(year))

    if not args.quiet:
        print(f"EEMT Streaming — SE Arizona {year}")
        print(f"{'='*60}", flush=True)

    t0 = time.time()
    os.makedirs(os.path.join(output_dir, "inputs"), exist_ok=True)
    os.makedirs(os.path.join(output_dir, "eemt"), exist_ok=True)

    # Read DEM
    if not args.quiet:
        print("\n[Phase 1] Loading inputs...", flush=True)
    dem = read_raster(DEM_PATH)
    valid = dem > 0
    if not args.quiet:
        print(f"  DEM: {dem.shape[1]}x{dem.shape[0]}, "
              f"elevation {np.min(dem[valid]):.0f}-{np.max(dem[valid]):.0f} m", flush=True)

    # Load shared inputs (cached from earlier run)
    shared_dir = OUTPUT_DIR
    slope_rad = read_raster(os.path.join(shared_dir, "inputs", "slope_rad.tif"))
    aspect_rad = read_raster(os.path.join(shared_dir, "inputs", "aspect_rad.tif"))
    twi = read_raster(os.path.join(shared_dir, "inputs", "twi.tif"))
    dem_1km = read_raster(os.path.join(shared_dir, "inputs", "dem_1km.tif"))
    if not args.quiet:
        print("  Loaded cached slope_rad, aspect_rad, twi, dem_1km", flush=True)

    # Phase 2: Compute EEMT
    if not args.quiet:
        print(f"\n[Phase 2] Computing EEMT daily for {year} (streaming)...", flush=True)
    monthly_results = compute_eemt_streaming(
        year, dem, dem_1km, valid, slope_rad, aspect_rad, twi,
        DEM_PATH, output_dir, quiet=args.quiet,
    )

    # Phase 3: Stats
    if not args.quiet:
        print(f"\n[Phase 3] Generating stats...", flush=True)
    csv_path = generate_stats(monthly_results, valid, year, output_dir)

    elapsed = time.time() - t0

    # Annual summary
    annual_trad = np.zeros_like(monthly_results[0]["EEMT_Trad"])
    for mr in monthly_results:
        et = mr["EEMT_Trad"].copy()
        et[~valid] = 0
        annual_trad += et
    annual_v = annual_trad[valid]

    print(f"{year}: EEMT mean={np.mean(annual_v):.1f} MJ/m2/yr, "
          f"range=[{np.min(annual_v):.1f}, {np.max(annual_v):.1f}], "
          f"elapsed={elapsed:.0f}s", flush=True)
    if not args.quiet:
        print(f"Stats: {csv_path}", flush=True)


if __name__ == "__main__":
    main()
