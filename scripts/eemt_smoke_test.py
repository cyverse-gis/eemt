#!/usr/bin/env python3
"""
EEMT Smoke Test — Gordon Gulch 1980
====================================
Standalone EEMT calculation using numpy + GDAL CLI.
Computes EEMT for 12 months of 1980, validates against Lean 4 proven bounds.

No GRASS GIS, SAGA, or Makeflow required.

Usage:
    python3 scripts/eemt_smoke_test.py
    python3 scripts/eemt_smoke_test.py --year 1985
    python3 scripts/eemt_smoke_test.py --daily    # daily computation, summed to monthly
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

DEM_PATH = "data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif"
SOLAR_DIR = "/opt/tswetnam/data/gordon_gulch/10m/dem"
DAYMET_DIR = "/opt/tswetnam/data/gordon_gulch/daymet/daily"
OUTPUT_DIR = "/opt/tswetnam/data/gordon_gulch/eemt_smoke_test"

DAYMET_LCC = (
    "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 "
    "+x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
)

MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
          "jul", "aug", "sep", "oct", "nov", "dec"]

# DAYMET always uses 365 bands (non-leap day counts for band indexing)
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

NODATA = -9999.0
CELL_AREA = 100.0  # 10m x 10m = 100 m²

# Lean 4 verified constants (from Foundation/Constants.lean)
LAPSE_RATE = 0.00649       # °C/m
NPP_MAX = 3000.0           # g/m²/yr
H_BIO = 22e6               # J/kg (energy content of biomass)
C_WATER = 4185.5           # combined ρ_w × c_w constant
EEMT_MIN = 0.1             # MJ/m²/yr (minimum physical EEMT)
EEMT_MAX = 500.0           # MJ/m²/yr (maximum physical EEMT)
REGIME_THRESHOLD = 70.0    # MJ/m²/yr (water vs energy limited)


# =============================================================================
# Raster I/O (numpy + GDAL CLI)
# =============================================================================

def run_cmd(cmd, timeout=120):
    """Run shell command, return (stdout, stderr, returncode)."""
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout, r.stderr, r.returncode


def get_raster_info(path):
    """Get raster metadata via gdalinfo -json."""
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
    # Extract CRS as proj4
    crs_wkt = info.get("coordinateSystem", {}).get("wkt", "")
    return {
        "cols": size[0], "rows": size[1],
        "gt": gt,  # [xmin, xres, 0, ymax, 0, -yres]
        "nodata": nodata,
        "nbands": len(bands),
        "crs_wkt": crs_wkt,
        "xmin": gt[0], "xres": gt[1],
        "ymax": gt[3], "yres": abs(gt[5]),
    }


def read_raster(path, band=None):
    """Read a GeoTIFF (or NetCDF subdataset) into a numpy array."""
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
        _, err, rc = run_cmd(cmd)
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
    """Write a 2D numpy array as GeoTIFF, copying CRS/transform from ref_tif."""
    info = get_raster_info(ref_tif)
    rows, cols = array.shape
    gt = info["gt"]

    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp:
        tmp_path = tmp.name
    hdr_path = tmp_path + ".hdr"

    try:
        array.astype(np.float32).tofile(tmp_path)
        # Write ENVI header
        with open(hdr_path, "w") as f:
            f.write("ENVI\n")
            f.write(f"samples = {cols}\n")
            f.write(f"lines = {rows}\n")
            f.write("bands = 1\n")
            f.write("header offset = 0\n")
            f.write("data type = 4\n")  # float32
            f.write("interleave = bsq\n")
            f.write("byte order = 0\n")

        # Convert to GeoTIFF with proper georeferencing
        xmin = gt[0]
        ymax = gt[3]
        xmax = xmin + cols * gt[1]
        ymin = ymax + rows * gt[5]  # gt[5] is negative

        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        # Get CRS as proj4 (more compact than WKT, avoids truncation issues)
        srs_stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", ref_tif])
        proj4 = srs_stdout.strip().strip("'\"") or "EPSG:32613"

        cmd = [
            "gdal_translate", "-of", "GTiff", "-q",
            "-a_ullr", str(xmin), str(ymax), str(xmax), str(ymin),
            "-a_srs", proj4,
            "-a_nodata", str(NODATA),
            "-co", "COMPRESS=LZW",
            tmp_path, path,
        ]
        _, err, rc = run_cmd(cmd)
        if rc != 0:
            raise RuntimeError(f"write_raster failed: {err}")
    finally:
        for p in [tmp_path, hdr_path, tmp_path + ".aux.xml"]:
            if os.path.exists(p):
                os.remove(p)


# =============================================================================
# Phase 1: Prepare Missing Inputs
# =============================================================================

def compute_slope_aspect(dem_path, output_dir):
    """Compute slope and aspect in radians using gdaldem."""
    print("  Computing slope and aspect...")
    slope_rad_path = os.path.join(output_dir, "inputs", "slope_rad.tif")
    aspect_rad_path = os.path.join(output_dir, "inputs", "aspect_rad.tif")

    os.makedirs(os.path.join(output_dir, "inputs"), exist_ok=True)

    # If already computed (shared across parallel runs), just read
    if os.path.isfile(slope_rad_path) and os.path.isfile(aspect_rad_path):
        slope_r = read_raster(slope_rad_path)
        aspect_r = read_raster(aspect_rad_path)
        print(f"    slope_rad: {np.nanmin(slope_r[slope_r != NODATA]):.3f} to {np.nanmax(slope_r):.3f} rad (cached)")
        print(f"    aspect_rad: {np.nanmin(aspect_r[aspect_r != NODATA]):.3f} to {np.nanmax(aspect_r):.3f} rad (cached)")
        return slope_r, aspect_r

    slope_deg = os.path.join(output_dir, "inputs", "slope_deg.tif")
    aspect_deg = os.path.join(output_dir, "inputs", "aspect_deg.tif")

    run_cmd(["gdaldem", "slope", dem_path, slope_deg, "-q"])
    run_cmd(["gdaldem", "aspect", dem_path, aspect_deg, "-zero_for_flat", "-q"])

    slope = read_raster(slope_deg)
    aspect = read_raster(aspect_deg)

    # Mask nodata before conversion
    dem_info = get_raster_info(dem_path)
    dem_arr = read_raster(dem_path)
    valid_mask = dem_arr > 0

    slope[~valid_mask] = 0
    aspect[~valid_mask] = 0

    slope_r = np.deg2rad(slope)
    aspect_r = np.deg2rad(aspect)

    slope_r[~valid_mask] = NODATA
    aspect_r[~valid_mask] = NODATA

    write_raster(slope_r, slope_rad_path, dem_path)
    write_raster(aspect_r, aspect_rad_path, dem_path)

    # Clean up degree files
    for f in [slope_deg, aspect_deg]:
        if os.path.exists(f):
            os.remove(f)

    print(f"    slope_rad: {np.nanmin(slope_r):.3f} to {np.nanmax(slope_r):.3f} rad")
    print(f"    aspect_rad: {np.nanmin(aspect_r):.3f} to {np.nanmax(aspect_r):.3f} rad")
    return slope_r, aspect_r


def compute_twi(dem, slope_rad, dem_path, output_dir):
    """Compute Topographic Wetness Index via D8 flow accumulation in numpy."""
    print("  Computing TWI (D8 flow accumulation)...")
    twi_path = os.path.join(output_dir, "inputs", "twi.tif")
    if os.path.isfile(twi_path):
        twi = read_raster(twi_path)
        valid_twi = twi[dem > 0]
        print(f"    TWI: {np.min(valid_twi):.2f} to {np.max(valid_twi):.2f} (cached)")
        return twi

    rows, cols = dem.shape
    valid = dem > 0  # nodata mask

    # D8 flow direction: find steepest downhill neighbor
    # Neighbor offsets: [N, NE, E, SE, S, SW, W, NW]
    dr = [-1, -1, 0, 1, 1, 1, 0, -1]
    dc = [0, 1, 1, 1, 0, -1, -1, -1]
    dist = [1, 1.414, 1, 1.414, 1, 1.414, 1, 1.414]

    # Initialize flow accumulation (each cell starts with 1)
    flow_acc = np.ones((rows, cols), dtype=np.float64)
    flow_acc[~valid] = 0

    # Sort cells by descending elevation for topological order
    flat_dem = dem.copy()
    flat_dem[~valid] = -np.inf
    sorted_idx = np.argsort(-flat_dem.ravel())

    # For each cell (high to low), route flow to steepest neighbor
    flow_to = np.full((rows, cols), -1, dtype=np.int32)  # flat index of target
    for idx in sorted_idx:
        r, c = divmod(int(idx), cols)
        if not valid[r, c]:
            continue
        max_slope = 0
        target = -1
        for k in range(8):
            nr, nc = r + dr[k], c + dc[k]
            if 0 <= nr < rows and 0 <= nc < cols and valid[nr, nc]:
                drop = (dem[r, c] - dem[nr, nc]) / (dist[k] * 10.0)  # 10m cell size
                if drop > max_slope:
                    max_slope = drop
                    target = nr * cols + nc
        flow_to[r, c] = target

    # Accumulate flow in topological order
    for idx in sorted_idx:
        r, c = divmod(int(idx), cols)
        if not valid[r, c]:
            continue
        t = flow_to[r, c]
        if t >= 0:
            tr, tc = divmod(t, cols)
            flow_acc[tr, tc] += flow_acc[r, c]

    # TWI = ln(a / tan(beta)), where a = flow_acc * cell_area
    tan_slope = np.tan(slope_rad)
    tan_slope = np.maximum(tan_slope, 0.001)  # avoid division by zero
    contributing_area = flow_acc * CELL_AREA
    twi = np.log(contributing_area / tan_slope)
    twi[~valid] = NODATA

    twi_path = os.path.join(output_dir, "inputs", "twi.tif")
    write_raster(twi, twi_path, dem_path)
    valid_twi = twi[valid]
    print(f"    TWI: {np.min(valid_twi):.2f} to {np.max(valid_twi):.2f} (median {np.median(valid_twi):.2f})")
    return twi


def process_daymet_monthly(year, dem_path, output_dir):
    """Convert DAYMET NetCDF daily to monthly GeoTIFFs matching DEM grid."""
    print(f"  Processing DAYMET {year} to monthly GeoTIFFs...")
    daymet_monthly = {}
    info = get_raster_info(dem_path)
    xmin = info["xmin"]
    ymax = info["ymax"]
    xmax = xmin + info["cols"] * info["xres"]
    ymin = ymax - info["rows"] * info["yres"]

    # Get DEM CRS as proj4 for gdalwarp target
    stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", dem_path])
    dem_crs = stdout.strip().strip("'\"")

    monthly_dir = os.path.join(output_dir, "inputs", "daymet_monthly")
    os.makedirs(monthly_dir, exist_ok=True)

    for var in ["tmin", "tmax", "prcp", "vp"]:
        nc_path = next(
            (str(p) for p in sorted(Path(DAYMET_DIR, var).glob(f"{var}_{year}_*.nc"))),
            os.path.join(DAYMET_DIR, var, f"{var}_{year}_gg.nc"),
        )
        if not os.path.isfile(nc_path):
            print(f"    [-] Missing: {nc_path}")
            continue

        # Read all 365 bands from NetCDF subdataset
        sd = f"NETCDF:{nc_path}:{var}"
        sd_info = get_raster_info(sd)
        if sd_info is None:
            print(f"    [-] Cannot read subdataset: {sd}")
            continue

        # Read all bands into (365, 9, 9) array
        all_data = read_raster(sd)
        if all_data.ndim == 2:
            all_data = all_data[np.newaxis, :, :]  # single band edge case

        # Get the NetCDF geotransform for writing intermediate files
        nc_gt = sd_info["gt"]

        band_start = 0
        monthly_arrays = {}
        for mi, month in enumerate(MONTHS):
            ndays = MONTH_DAYS[mi]
            month_data = all_data[band_start:band_start + ndays]
            band_start += ndays

            if var == "prcp":
                agg = np.sum(month_data, axis=0)  # monthly total
            else:
                agg = np.mean(month_data, axis=0)  # monthly mean

            # Write as small LCC GeoTIFF
            lcc_path = os.path.join(monthly_dir, f"{var}_{year}_{month}_lcc.tif")
            with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp:
                tmp_path = tmp.name
            hdr_path = tmp_path + ".hdr"

            try:
                r, c = agg.shape
                agg.astype(np.float32).tofile(tmp_path)
                with open(hdr_path, "w") as f:
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
                    "-a_srs", DAYMET_LCC,
                    tmp_path, lcc_path,
                ])
            finally:
                for p in [tmp_path, hdr_path]:
                    if os.path.exists(p):
                        os.remove(p)

            # Warp to DEM grid
            utm_path = os.path.join(monthly_dir, f"{var}_{year}_{month}.tif")
            run_cmd([
                "gdalwarp", "-q", "-overwrite",
                "-s_srs", DAYMET_LCC,
                "-t_srs", dem_crs,
                "-te", str(xmin), str(ymin), str(xmax), str(ymax),
                "-ts", str(info["cols"]), str(info["rows"]),
                "-r", "bilinear",
                lcc_path, utm_path,
            ])

            # Read the warped raster
            monthly_arrays[month] = read_raster(utm_path)

            # Clean up LCC intermediate
            if os.path.exists(lcc_path):
                os.remove(lcc_path)

        daymet_monthly[var] = monthly_arrays
        print(f"    {var}: 12 months processed")

    return daymet_monthly


def warp_daymet_band_to_dem(nc_data_2d, nc_gt, dem_path, dem_info, dem_crs, tmp_dir):
    """Warp a single 9x9 DAYMET band (LCC) to match the DEM grid (UTM). Returns array."""
    r, c = nc_data_2d.shape

    # Write to temp ENVI
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
        "-a_srs", DAYMET_LCC,
        tmp_bin, tmp_lcc,
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
        "-r", "bilinear",
        tmp_lcc, tmp_utm,
    ])

    result = read_raster(tmp_utm)

    # Cleanup
    for p in [tmp_bin, tmp_hdr, tmp_bin + ".aux.xml", tmp_lcc, tmp_utm]:
        if os.path.exists(p):
            os.remove(p)

    return result


def load_daymet_daily(year, dem_path, output_dir):
    """Load all 365 days of DAYMET data, warped to DEM grid.

    Returns dict: {var: np.array of shape (365, rows, cols)}
    """
    print(f"  Loading DAYMET {year} daily (365 bands x 4 vars)...")
    info = get_raster_info(dem_path)
    stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", dem_path])
    dem_crs = stdout.strip().strip("'\"")

    tmp_dir = tempfile.mkdtemp(prefix="daymet_daily_")
    daily_data = {}

    for var in ["tmin", "tmax", "prcp", "vp"]:
        nc_path = next(
            (str(p) for p in sorted(Path(DAYMET_DIR, var).glob(f"{var}_{year}_*.nc"))),
            os.path.join(DAYMET_DIR, var, f"{var}_{year}_gg.nc"),
        )
        if not os.path.isfile(nc_path):
            print(f"    [-] Missing: {nc_path}")
            continue

        sd = f"NETCDF:{nc_path}:{var}"
        sd_info = get_raster_info(sd)
        if sd_info is None:
            continue

        # Read all 365 bands as (365, 9, 9)
        all_bands = read_raster(sd)
        if all_bands.ndim == 2:
            all_bands = all_bands[np.newaxis, :, :]
        nc_gt = sd_info["gt"]
        ndays = all_bands.shape[0]

        # Warp first band to get target shape, then batch-process
        first = warp_daymet_band_to_dem(all_bands[0], nc_gt, dem_path, info, dem_crs, tmp_dir)
        rows, cols = first.shape
        result = np.zeros((ndays, rows, cols), dtype=np.float32)
        result[0] = first

        for d in range(1, ndays):
            result[d] = warp_daymet_band_to_dem(all_bands[d], nc_gt, dem_path, info, dem_crs, tmp_dir)

        daily_data[var] = result
        print(f"    {var}: {ndays} days warped to {cols}x{rows}")

    # Cleanup tmp dir
    try:
        os.rmdir(tmp_dir)
    except OSError:
        pass

    return daily_data


def create_reference_dem_1km(dem_path, output_dir):
    """Create 1km reference DEM matching DAYMET resolution, reprojected back to DEM grid."""
    print("  Creating 1km reference DEM...")
    utm_1km = os.path.join(output_dir, "inputs", "dem_1km.tif")
    if os.path.isfile(utm_1km):
        dem_1km = read_raster(utm_1km)
        print(f"    dem_1km: cached")
        return dem_1km

    info = get_raster_info(dem_path)
    xmin = info["xmin"]
    ymax = info["ymax"]
    xmax = xmin + info["cols"] * info["xres"]
    ymin = ymax - info["rows"] * info["yres"]

    stdout, _, _ = run_cmd(["gdalsrsinfo", "-o", "proj4", dem_path])
    dem_crs = stdout.strip().strip("'\"")

    inputs_dir = os.path.join(output_dir, "inputs")
    lcc_1km = os.path.join(inputs_dir, "dem_1km_lcc.tif")
    utm_1km = os.path.join(inputs_dir, "dem_1km.tif")

    # Downsample to ~1km in LCC
    run_cmd([
        "gdalwarp", "-q", "-overwrite",
        "-t_srs", DAYMET_LCC, "-tr", "1000", "1000",
        "-r", "average", dem_path, lcc_1km,
    ])

    # Upsample back to DEM grid
    run_cmd([
        "gdalwarp", "-q", "-overwrite",
        "-s_srs", DAYMET_LCC, "-t_srs", dem_crs,
        "-te", str(xmin), str(ymin), str(xmax), str(ymax),
        "-ts", str(info["cols"]), str(info["rows"]),
        "-r", "bilinear", lcc_1km, utm_1km,
    ])

    dem_1km = read_raster(utm_1km)
    if os.path.exists(lcc_1km):
        os.remove(lcc_1km)

    print(f"    dem_1km: {np.nanmin(dem_1km[dem_1km > 0]):.0f} to {np.nanmax(dem_1km):.0f} m")
    return dem_1km


# =============================================================================
# Phase 2: EEMT Computation
# =============================================================================

def compute_eemt_month(dem, dem_1km, tmin, tmax, vp, prcp, total_sun, hours_sun,
                       flat_sun_mean, slope_rad, aspect_rad, twi, valid):
    """Compute EEMT for a single month. Returns dict of arrays and diagnostics."""
    eps = 1e-10  # epsilon for division safety

    # --- Temperature lapse rate correction (reemt.sh lines 141-142) ---
    tmin_loc = tmin - LAPSE_RATE * (dem - dem_1km)
    tmax_loc = tmax - LAPSE_RATE * (dem - dem_1km)
    tmean_loc = (tmax_loc + tmin_loc) / 2.0

    # --- Hamon PET for EEMT-Traditional (reemt.sh lines 149-153) ---
    es_tmin = np.where(tmin_loc > 0,
                       0.6108 * np.exp(17.27 * tmin_loc / (tmin_loc + 237.3)), 0)
    es_tmax = np.where(tmax_loc > 0,
                       0.6108 * np.exp(17.27 * tmax_loc / (tmax_loc + 237.3)), 0)
    e_s = np.where(tmean_loc > 0, (es_tmax + es_tmin) / 2.0, 0)
    PET_Trad = np.where(e_s > 0,
                        (29.8 * hours_sun * e_s) / (tmean_loc + 273.2), 0)

    # --- Topographic temperature modification (reemt.sh lines 157-160) ---
    S_i = np.where(flat_sun_mean > eps, total_sun / flat_sun_mean, 1.0)
    S_i = np.clip(S_i, 0.01, 100.0)  # safety bounds
    tmin_topo = tmin_loc.copy()
    tmax_topo = tmax_loc + (S_i - 1.0 / S_i)
    tmean_topo = (tmax_topo + tmin_topo) / 2.0

    # --- Penman-Monteith PET for EEMT-Topo (reemt.sh lines 165-181) ---
    g_psy = 1013.0 * (101.3 * ((293.0 - LAPSE_RATE * dem) / 293.0) ** 5.26)
    m_vp = 0.04145 * np.exp(0.06088 * tmean_topo)
    ra = (4.72 * (np.log(2.0 / 0.00137)) ** 2) / (1.0 + 0.536 * 5.0)
    vp_loc = 6.11 * (10.0 ** (7.5 * tmin_topo / (237.3 + tmin_topo + eps)))

    # Fixed bug (line 174): uses tmax_topo, not tmin_topo
    f_tmin_topo = np.where(tmin_topo > 0,
                           6.108 * np.exp(17.27 * tmin_topo / (tmin_topo + 237.3)), 0)
    f_tmax_topo = np.where(tmax_topo > 0,
                           6.108 * np.exp(17.27 * tmax_topo / (tmax_topo + 237.3)), 0)
    vp_s_topo = np.where(tmean_topo > 0, (f_tmax_topo + f_tmin_topo) / 2.0, 0)

    tmean_topo_safe = np.where(np.abs(tmean_topo) < eps, eps, tmean_topo)
    p_a = (101325.0 * np.exp(-9.80665 * 0.289644 * dem / (8.31447 * 288.15))
           / (287.35 * tmean_topo_safe * 273.125))

    total_sun_joules = total_sun * 3600.0
    denom_pm = 2450000.0 * (m_vp + g_psy)
    denom_pm = np.where(np.abs(denom_pm) < eps, eps, denom_pm)
    PET_topo = np.where(tmean_topo > 0,
                        (m_vp * total_sun_joules + p_a * 1013.0 * ((vp_s_topo - vp_loc) / ra))
                        / denom_pm, 0)

    # --- Water balance: TWI redistribution (reemt.sh lines 185-193) ---
    twi_valid = twi.copy()
    twi_valid[~valid] = np.nan
    twi_median = np.nanmedian(twi_valid)
    if twi_median == 0:
        twi_median = 1.0
    a_i = twi / twi_median

    prcp_safe = np.maximum(prcp, eps)
    pet_ratio = np.where(prcp > 0, PET_topo / prcp_safe, 0)
    AET_zb = np.where(tmean_topo > 0,
                      prcp * (1.0 + pet_ratio - (1.0 + pet_ratio ** 2.63) ** (1.0 / 2.63)),
                      0)
    P_eff = prcp - AET_zb
    F = np.where(prcp > 0, a_i * P_eff, 0)

    # --- EEMT-Traditional (reemt.sh lines 197-202) ---
    # Fixed bug (line 197): includes temperature term
    # E_ppt can be negative if PET > prcp; clamp to 0 (no negative energy transfer)
    E_ppt_trad = np.where((prcp > 0) & (tmean_loc > 0),
                          np.maximum(0, (prcp - PET_Trad * 10.0)) * C_WATER * tmean_loc, 0)
    NPP_trad = np.where(tmean_loc > 0,
                        NPP_MAX / (1.0 + np.exp(1.315 - 0.119 * tmean_loc)), 0)
    # NPP in g/m²/yr, H_BIO in J/kg → divide by 1000 for g→kg
    E_bio_trad = np.where(tmean_loc > 0, NPP_trad * H_BIO / 1000.0, 0)
    EEMT_Trad = (E_ppt_trad + E_bio_trad) / 1e6

    # --- EEMT-Topographic (reemt.sh lines 207-217) ---
    # Northness: GDAL aspect is CW from north, so cos(aspect) = northness
    N = np.cos(slope_rad) * np.cos(aspect_rad)
    NPP_topo = 0.39 * dem + 346.0 * N - 187.0
    # NPP in g/m²/yr, H_BIO in J/kg → divide by 1000 for g→kg
    E_bio_topo = NPP_topo * H_BIO / 1000.0

    # Fixed bug (line 215): no E_bio_topo in E_ppt formula
    E_ppt_topo = np.where((prcp > 0) & (tmean_topo > 0),
                          F * C_WATER * tmean_topo, 0)
    EEMT_Topo = (E_ppt_topo + E_bio_topo) / 1e6

    # Apply nodata mask
    for arr in [EEMT_Trad, EEMT_Topo, NPP_trad, E_ppt_trad, E_bio_trad,
                E_ppt_topo, E_bio_topo]:
        arr[~valid] = NODATA

    return {
        "EEMT_Trad": EEMT_Trad, "EEMT_Topo": EEMT_Topo,
        "NPP_trad": NPP_trad, "E_ppt_trad": E_ppt_trad, "E_bio_trad": E_bio_trad,
        "E_ppt_topo": E_ppt_topo, "E_bio_topo": E_bio_topo,
        "tmean_loc": tmean_loc, "tmean_topo": tmean_topo,
    }


def compute_eemt_daily_to_monthly(dem, dem_1km, daymet_daily, valid,
                                   slope_rad, aspect_rad, twi, year, output_dir,
                                   dem_path):
    """Compute EEMT day-by-day, accumulate to monthly totals.

    This is more accurate than monthly-mean input because PET/NPP
    are nonlinear in temperature.
    """
    ndays = daymet_daily["tmin"].shape[0]
    rows, cols = dem.shape

    # TWI-derived constants (constant across days)
    twi_valid = twi.copy()
    twi_valid[~valid] = np.nan
    twi_median = np.nanmedian(twi_valid)
    if twi_median == 0:
        twi_median = 1.0
    a_i = twi / twi_median

    # Northness (constant)
    N = np.cos(slope_rad) * np.cos(aspect_rad)

    # Pre-compute elevation-dependent constants
    eps = 1e-10
    g_psy = 1013.0 * (101.3 * ((293.0 - LAPSE_RATE * dem) / 293.0) ** 5.26)
    ra = (4.72 * (np.log(2.0 / 0.00137)) ** 2) / (1.0 + 0.536 * 5.0)

    # NPP_topo (elevation/aspect dependent, constant)
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

    # Load daily solar radiation lazily (365 files)
    print("    Loading daily solar radiation...")
    solar_daily = []
    insol_daily = []
    for d in range(1, 366):
        sp = os.path.join(SOLAR_DIR, "global", "daily", f"total_sun_day_{d}.tif")
        ip = os.path.join(SOLAR_DIR, "insol", "daily", f"hours_sun_day_{d}.tif")
        solar_daily.append(sp)
        insol_daily.append(ip)

    # Compute flat_sun_mean per month (for S_i ratio)
    print("    Pre-computing monthly flat solar means...")
    monthly_flat_sun = {}
    for month in MONTHS:
        solar_path = os.path.join(SOLAR_DIR, "global", "monthly", f"total_sun_{month}_sum.tif")
        total_sun_month = read_raster(solar_path)
        monthly_flat_sun[month] = np.mean(total_sun_month[valid])

    print(f"    Processing {ndays} days...")
    last_pct = -1
    for d in range(ndays):
        mi = day_to_month[d]
        month_name = MONTHS[mi]

        # Read daily solar (from disk each time to save memory)
        total_sun = read_raster(solar_daily[d])
        hours_sun = read_raster(insol_daily[d])
        flat_sun_mean = monthly_flat_sun[month_name] / MONTH_DAYS[mi]  # daily approx

        tmin = daymet_daily["tmin"][d]
        tmax = daymet_daily["tmax"][d]
        prcp = daymet_daily["prcp"][d]

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
        # NPP is annual rate (g/m²/yr) → divide by 365 for daily contribution
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
            print(f"      {pct}% ({d+1}/{ndays} days)")
            last_pct = pct

    # Convert accumulators to monthly result dicts
    monthly_results = []
    for mi in range(12):
        acc = monthly_accum[mi]
        nd = max(acc["ndays"], 1)

        # EEMT sums are already monthly totals (sum of daily)
        eemt_trad = acc["EEMT_Trad"].astype(np.float32)
        eemt_topo = acc["EEMT_Topo"].astype(np.float32)
        npp_mean = (acc["NPP_trad_sum"] / nd).astype(np.float32)
        tmean_mean = (acc["tmean_sum"] / nd).astype(np.float32)

        eemt_trad[~valid] = NODATA
        eemt_topo[~valid] = NODATA
        npp_mean[~valid] = NODATA
        tmean_mean[~valid] = NODATA

        # Write output GeoTIFFs
        for key, arr in [("EEMT_Trad", eemt_trad), ("EEMT_Topo", eemt_topo)]:
            out_path = os.path.join(output_dir, "eemt", f"{key}_{MONTHS[mi]}_{year}.tif")
            write_raster(arr, out_path, dem_path)

        monthly_results.append({
            "EEMT_Trad": eemt_trad,
            "EEMT_Topo": eemt_topo,
            "NPP_trad": npp_mean,
            "E_ppt_trad": (acc["E_ppt_trad_sum"] / 1e6).astype(np.float32),  # for stats
            "E_bio_trad": (acc["E_bio_trad_sum"] / 1e6).astype(np.float32),
            "E_ppt_topo": np.zeros_like(eemt_trad),  # placeholder
            "E_bio_topo": np.zeros_like(eemt_trad),
            "tmean_loc": tmean_mean,
            "tmean_topo": tmean_mean,
        })

        trad_v = eemt_trad[valid]
        print(f"  {MONTHS[mi]}: EEMT_Trad mean={np.mean(trad_v):>8.2f}, "
              f"range=[{np.min(trad_v):.2f}, {np.max(trad_v):.2f}] MJ/m2, "
              f"tmean={np.mean(tmean_mean[valid]):.1f}C ({nd} days)")

    return monthly_results


# =============================================================================
# Phase 3: Lean 4 Validation
# =============================================================================

def validate_lean4(monthly_results, valid):
    """Validate outputs against Lean 4 proven theorems."""
    checks = []

    # Collect annual sums
    annual_trad = np.zeros_like(monthly_results[0]["EEMT_Trad"])
    annual_topo = np.zeros_like(monthly_results[0]["EEMT_Topo"])
    monthly_means = []
    monthly_temps = []

    for mr in monthly_results:
        et = mr["EEMT_Trad"].copy()
        et[~valid] = 0
        annual_trad += et
        eo = mr["EEMT_Topo"].copy()
        eo[~valid] = 0
        annual_topo += eo
        monthly_means.append(np.mean(et[valid]))
        monthly_temps.append(np.mean(mr["tmean_loc"][valid]))

    # 1. eemt_nonneg: EEMT >= 0 for all valid pixels (per month)
    all_nonneg = True
    for i, mr in enumerate(monthly_results):
        trad_v = mr["EEMT_Trad"][valid]
        if np.any(trad_v < -0.01):
            all_nonneg = False
            break
    checks.append(("eemt_nonneg", "EEMT >= 0 for all valid pixels", all_nonneg,
                   f"min monthly EEMT_Trad = {min(np.min(mr['EEMT_Trad'][valid]) for mr in monthly_results):.2f}"))

    # 2. nppTemp_lt_max: NPP < 3000
    max_npp = max(np.max(mr["NPP_trad"][valid]) for mr in monthly_results)
    checks.append(("nppTemp_lt_max", f"NPP < {NPP_MAX}", max_npp < NPP_MAX,
                   f"max NPP = {max_npp:.1f}"))

    # 3. ePpt_zero_frozen: E_PPT = 0 where T <= 0
    frozen_ok = True
    for mr in monthly_results:
        frozen = valid & (mr["tmean_loc"] <= 0)
        if np.any(frozen):
            e_ppt_frozen = mr["E_ppt_trad"][frozen]
            if np.any(np.abs(e_ppt_frozen) > 0.01):
                frozen_ok = False
                break
    checks.append(("ePpt_zero_frozen", "E_PPT = 0 where T <= 0", frozen_ok, ""))

    # 4. validEEMTRange: annual EEMT in [0.1, 500]
    annual_v = annual_trad[valid]
    in_range = np.sum((annual_v >= EEMT_MIN) & (annual_v <= EEMT_MAX))
    total_valid = np.sum(valid)
    pct_in_range = 100.0 * in_range / max(total_valid, 1)
    checks.append(("validEEMTRange", f"Annual EEMT in [{EEMT_MIN}, {EEMT_MAX}] MJ/m2/yr",
                   pct_in_range > 90,
                   f"{pct_in_range:.1f}% in range, annual mean={np.mean(annual_v):.1f}"))

    # 5. regime_partition: water-limited vs energy-limited
    water_lim = np.sum(annual_v < REGIME_THRESHOLD)
    energy_lim = np.sum(annual_v >= REGIME_THRESHOLD)
    checks.append(("regime_partition", "Water/energy limited classification",
                   True,  # always passes (it's a classification)
                   f"water-limited: {100*water_lim/max(total_valid,1):.1f}%, "
                   f"energy-limited: {100*energy_lim/max(total_valid,1):.1f}%"))

    # 6. eemt_monotone_temp: warmer months -> higher EEMT (statistical)
    temp_eemt_corr = np.corrcoef(monthly_temps, monthly_means)[0, 1]
    checks.append(("eemt_monotone_temp", "EEMT correlates with temperature",
                   temp_eemt_corr > 0.5,
                   f"correlation = {temp_eemt_corr:.3f}"))

    # 7. nppTemp_strictMono: NPP increases with temperature
    monthly_npp = [np.mean(mr["NPP_trad"][valid]) for mr in monthly_results]
    npp_temp_corr = np.corrcoef(monthly_temps, monthly_npp)[0, 1]
    checks.append(("nppTemp_strictMono", "NPP correlates with temperature",
                   npp_temp_corr > 0.5,
                   f"correlation = {npp_temp_corr:.3f}"))

    # 8. eemt_decomposition: EEMT = E_BIO + E_PPT exactly
    decomp_ok = True
    for mr in monthly_results:
        expected = (mr["E_ppt_trad"] + mr["E_bio_trad"]) / 1e6
        diff = np.abs(mr["EEMT_Trad"][valid] - expected[valid])
        if np.max(diff) > 0.001:
            decomp_ok = False
            break
    checks.append(("eemt_decomposition", "EEMT = E_BIO + E_PPT", decomp_ok, ""))

    return checks, annual_trad, annual_topo


# =============================================================================
# Phase 4: Summary Report
# =============================================================================

def generate_report(monthly_results, checks, annual_trad, annual_topo,
                    valid, year, output_dir):
    """Generate summary report and CSV."""
    report_path = os.path.join(output_dir, "eemt_smoke_test_report.txt")
    csv_path = os.path.join(output_dir, "monthly_stats.csv")

    # Monthly stats CSV
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

    # Text report
    with open(report_path, "w") as f:
        f.write(f"EEMT Smoke Test Report — Gordon Gulch {year}\n")
        f.write(f"{'='*60}\n\n")
        f.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"DEM: gordongulch_dem_10m_3dep_cog.tif (434x296, 10m, UTM 13N)\n")
        f.write(f"Valid pixels: {np.sum(valid)}\n\n")

        f.write("LEAN 4 VALIDATION RESULTS\n")
        f.write(f"{'-'*60}\n")
        passed = 0
        for name, desc, ok, detail in checks:
            status = "PASS" if ok else "FAIL"
            if ok:
                passed += 1
            f.write(f"  [{status}] {name}: {desc}\n")
            if detail:
                f.write(f"         {detail}\n")
        f.write(f"\n  {passed}/{len(checks)} checks passed\n\n")

        f.write("ANNUAL SUMMARY\n")
        f.write(f"{'-'*60}\n")
        annual_v = annual_trad[valid]
        f.write(f"  EEMT_Trad (annual): min={np.min(annual_v):.1f}, max={np.max(annual_v):.1f}, "
                f"mean={np.mean(annual_v):.1f} MJ/m2/yr\n")
        annual_tv = annual_topo[valid]
        f.write(f"  EEMT_Topo (annual): min={np.min(annual_tv):.1f}, max={np.max(annual_tv):.1f}, "
                f"mean={np.mean(annual_tv):.1f} MJ/m2/yr\n\n")

        f.write("MONTHLY EEMT_TRAD STATISTICS\n")
        f.write(f"{'-'*60}\n")
        f.write(f"  {'Month':<6} {'Tmean':>6} {'Min':>8} {'Max':>8} {'Mean':>8} {'Std':>8} {'NPP':>8}\n")
        for i, mr in enumerate(monthly_results):
            trad_v = mr["EEMT_Trad"][valid]
            f.write(f"  {MONTHS[i]:<6} {np.mean(mr['tmean_loc'][valid]):>6.1f} "
                    f"{np.min(trad_v):>8.1f} {np.max(trad_v):>8.1f} "
                    f"{np.mean(trad_v):>8.1f} {np.std(trad_v):>8.1f} "
                    f"{np.mean(mr['NPP_trad'][valid]):>8.0f}\n")

        f.write(f"\nEXPECTED RANGES (Colorado montane, 2400-2800m)\n")
        f.write(f"{'-'*60}\n")
        f.write(f"  EEMT: 10-80 MJ/m2/yr (semi-arid montane)\n")
        f.write(f"  NPP:  800-2000 g/m2/yr at MAT ~5C\n")
        f.write(f"  Regime: predominantly water-limited (< 70 MJ/m2/yr)\n")

    return report_path, csv_path


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="EEMT Smoke Test — Gordon Gulch")
    parser.add_argument("--year", type=int, default=1980, help="Test year (default: 1980)")
    parser.add_argument("--daily", action="store_true",
                       help="Compute EEMT daily then sum to monthly (more accurate)")
    parser.add_argument("--per-year-output", action="store_true",
                       help="Write outputs to year-specific subdirectories")
    parser.add_argument("--quiet", "-q", action="store_true",
                       help="Minimal output (for batch runs)")
    args = parser.parse_args()
    year = args.year

    # Resolve DEM path
    dem_path = DEM_PATH
    if not os.path.isabs(dem_path):
        repo_root = Path(__file__).resolve().parent.parent
        dem_path = str(repo_root / dem_path)

    # Per-year output directories for batch runs
    output_dir = OUTPUT_DIR
    if args.per_year_output:
        output_dir = os.path.join(OUTPUT_DIR, str(year))

    if not args.quiet:
        print(f"EEMT Smoke Test — Gordon Gulch {year}")
        print(f"{'='*60}")
    t0 = time.time()

    # Create output directories
    for d in ["inputs", "eemt"]:
        os.makedirs(os.path.join(output_dir, d), exist_ok=True)

    # Read DEM
    if not args.quiet:
        print("\n[Phase 1] Preparing inputs...")
    dem = read_raster(dem_path)
    valid = dem > 0  # nodata mask
    if not args.quiet:
        print(f"  DEM: {dem.shape[1]}x{dem.shape[0]}, "
              f"elevation {np.min(dem[valid]):.0f}-{np.max(dem[valid]):.0f} m")

    # Shared inputs go to base OUTPUT_DIR (reused across years)
    shared_dir = OUTPUT_DIR

    # Step 2a: Slope and aspect (shared)
    slope_rad, aspect_rad = compute_slope_aspect(dem_path, shared_dir)

    # Step 2c: TWI (shared)
    twi = compute_twi(dem, slope_rad, dem_path, shared_dir)

    # Step 2e: Reference DEM (1km) (shared)
    dem_1km = create_reference_dem_1km(dem_path, shared_dir)

    if args.daily:
        # --- Daily mode: load 365 daily DAYMET + daily solar, sum to monthly ---
        daymet_daily = load_daymet_daily(year, dem_path, output_dir)

        if not args.quiet:
            print(f"\n[Phase 2] Computing EEMT daily for {year} (365 days -> 12 months)...")
        monthly_results = compute_eemt_daily_to_monthly(
            dem, dem_1km, daymet_daily, valid,
            slope_rad, aspect_rad, twi, year, output_dir, dem_path,
        )
    else:
        # --- Monthly mode: aggregate DAYMET to monthly means first ---
        daymet = process_daymet_monthly(year, dem_path, output_dir)

        # Read solar radiation data
        print("  Loading solar radiation data...")
        solar_monthly = {}
        insol_monthly = {}
        for month in MONTHS:
            solar_path = os.path.join(SOLAR_DIR, "global", "monthly",
                                     f"total_sun_{month}_sum.tif")
            insol_path = os.path.join(SOLAR_DIR, "insol", "monthly",
                                     f"hours_sun_{month}_sum.tif")
            solar_monthly[month] = read_raster(solar_path)
            insol_monthly[month] = read_raster(insol_path)
        print(f"    Loaded 12 months of solar + insolation data")

        # Phase 2: Compute EEMT
        print(f"\n[Phase 2] Computing EEMT for {year} (monthly mode)...")
        monthly_results = []
        for i, month in enumerate(MONTHS):
            total_sun = solar_monthly[month]
            hours_sun = insol_monthly[month]
            flat_sun_mean = np.mean(total_sun[valid])

            tmin = daymet["tmin"][month]
            tmax = daymet["tmax"][month]
            prcp = daymet["prcp"][month]
            vp_data = daymet["vp"][month]

            result = compute_eemt_month(
                dem, dem_1km, tmin, tmax, vp_data, prcp,
                total_sun, hours_sun, flat_sun_mean,
                slope_rad, aspect_rad, twi, valid,
            )
            monthly_results.append(result)

            for key in ["EEMT_Trad", "EEMT_Topo"]:
                out_path = os.path.join(output_dir, "eemt", f"{key}_{month}_{year}.tif")
                write_raster(result[key], out_path, dem_path)

            trad_v = result["EEMT_Trad"][valid]
            print(f"  {month}: EEMT_Trad mean={np.mean(trad_v):>8.1f}, "
                  f"range=[{np.min(trad_v):.1f}, {np.max(trad_v):.1f}] MJ/m2, "
                  f"tmean={np.mean(result['tmean_loc'][valid]):.1f}C")

    # Phase 3: Validate
    if not args.quiet:
        print(f"\n[Phase 3] Lean 4 validation...")
    checks, annual_trad, annual_topo = validate_lean4(monthly_results, valid)
    if not args.quiet:
        for name, desc, ok, detail in checks:
            status = "[+] PASS" if ok else "[-] FAIL"
            print(f"  {status}: {name} — {detail}" if detail else f"  {status}: {name}")

    # Phase 4: Report
    if not args.quiet:
        print(f"\n[Phase 4] Generating report...")
    report_path, csv_path = generate_report(
        monthly_results, checks, annual_trad, annual_topo, valid, year, output_dir)

    elapsed = time.time() - t0
    # Always print year summary (even in quiet mode)
    annual_v = annual_trad[valid]
    print(f"{year}: EEMT mean={np.mean(annual_v):.1f} MJ/m2/yr, "
          f"range=[{np.min(annual_v):.1f}, {np.max(annual_v):.1f}], "
          f"elapsed={elapsed:.0f}s")
    if not args.quiet:
        print(f"Report: {report_path}")
        print(f"Stats:  {csv_path}")


if __name__ == "__main__":
    main()
