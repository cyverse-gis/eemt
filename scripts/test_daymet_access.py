#!/usr/bin/env python3
"""
Test DAYMET v4 API Access for Gordon Gulch Study Area
=====================================================
Validates ORNL DAAC DAYMET endpoints, downloads sample data,
and converts NetCDF to GeoTIFF for the EEMT workflow.

THREDDS/NCSS access requires NASA Earthdata Login credentials.
Set up a ~/.netrc file with:

    machine urs.earthdata.nasa.gov
        login YOUR_USERNAME
        password YOUR_PASSWORD

Register at: https://urs.earthdata.nasa.gov/users/new

Usage:
    python scripts/test_daymet_access.py
    python scripts/test_daymet_access.py --year 2015 --output-dir /path/to/output
    python scripts/test_daymet_access.py --skip-download  # validate existing files only
"""

import argparse
import json
import netrc
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import requests

# =============================================================================
# Configuration
# =============================================================================

# Gordon Gulch WGS84 bounding box (from NHDPlus catchment GeoJSON)
GORDON_GULCH_BBOX = {
    "north": 40.025,
    "south": 40.011,
    "east": -105.467,
    "west": -105.493,
}

# Buffered bbox (~1km buffer for full DAYMET pixel coverage)
BBOX_BUFFER = 0.01  # degrees

# DAYMET variables needed for EEMT
DAYMET_VARS = ["tmin", "tmax", "prcp", "vp"]

# DAYMET LCC projection (from eemt/eemt/Tiff.py line 8)
DAYMET_LCC_PROJ = (
    "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 "
    "+x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
)

# API endpoints
SINGLE_PIXEL_URL = "https://daymet.ornl.gov/single-pixel/api/data"
CMR_SEARCH_URL = "https://cmr.earthdata.nasa.gov/search"

# OPeNDAP endpoint (ORNL THREDDS redirects here; requires Earthdata auth)
OPENDAP_BASE = "https://opendap.earthdata.nasa.gov/collections"

# CMR collection concept IDs (discovered via CMR search)
CMR_COLLECTIONS = {
    "daily": "C2532426483-ORNL_CLOUD",    # Daymet_Daily_V4R1_2129
    "monthly": "C2532007210-ORNL_CLOUD",  # Daymet_Monthly_V4R1_2131
}

# DAYMET grid parameters (from OPeNDAP DMR metadata)
# Grid: 8075 y-pixels x 7814 x-pixels, 1km spacing, LCC projection
DAYMET_GRID = {
    "y_first": 4984000.0,  # north edge (index 0)
    "y_last": -3090000.0,  # south edge (index 8074)
    "y_size": 8075,
    "x_first": -4560250.0,  # west edge (index 0)
    "x_last": 3251750.0,   # east edge (index 7813)
    "x_size": 7814,
    "step": 1000.0,         # meters
}

# Default paths
DEFAULT_DEM = "data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif"
DEFAULT_OUTPUT = "/opt/tswetnam/data/gordon_gulch/daymet"
DEFAULT_YEAR = 2020

# Sample days to convert to GeoTIFF (1-indexed band numbers)
SAMPLE_DAYS = [1, 182]  # Jan 1 and Jul 1


# =============================================================================
# Utilities
# =============================================================================

def buffered_bbox(bbox, buffer=BBOX_BUFFER):
    """Add buffer to bounding box for full pixel coverage."""
    return {
        "north": bbox["north"] + buffer,
        "south": bbox["south"] - buffer,
        "east": bbox["east"] + buffer,
        "west": bbox["west"] - buffer,
    }


def run_cmd(cmd, capture=True):
    """Run a shell command and return stdout."""
    result = subprocess.run(
        cmd, capture_output=capture, text=True, timeout=120
    )
    if result.returncode != 0:
        return None, result.stderr
    return result.stdout, None


def fmt_size(nbytes):
    """Format byte count as human-readable string."""
    for unit in ["B", "KB", "MB", "GB"]:
        if nbytes < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} TB"


def print_header(title):
    print(f"\n{'='*72}")
    print(f"  {title}")
    print(f"{'='*72}")


def print_result(name, passed, detail=""):
    status = "PASS" if passed else "FAIL"
    marker = "[+]" if passed else "[-]"
    print(f"  {marker} {name}: {status}  {detail}")


# =============================================================================
# Earthdata Authentication
# =============================================================================

# ORNL DAAC THREDDS redirects to opendap.earthdata.nasa.gov (Hyrax/OPeNDAP)
# which requires NASA Earthdata URS authentication via .netrc


def get_earthdata_credentials():
    """Read Earthdata credentials from ~/.netrc."""
    try:
        nrc = netrc.netrc()
        auth = nrc.authenticators("urs.earthdata.nasa.gov")
        if auth:
            return auth[0], auth[2]  # login, password
    except (FileNotFoundError, netrc.NetrcParseError):
        pass
    return None, None


def create_earthdata_session():
    """Verify Earthdata credentials work via the URS token endpoint."""
    username, password = get_earthdata_credentials()
    if not username:
        return None, "No Earthdata credentials in ~/.netrc"

    print("  Verifying Earthdata credentials...")
    try:
        resp = requests.get(
            "https://urs.earthdata.nasa.gov/api/users/tokens",
            auth=(username, password),
            timeout=15,
        )
        if resp.status_code == 200:
            print(f"  [+] Earthdata auth verified (user: {username})")
            return True, None
        else:
            return None, f"Earthdata auth failed (HTTP {resp.status_code})"
    except requests.RequestException as e:
        return None, f"Earthdata auth error: {e}"


def bbox_to_lcc(bbox):
    """Convert WGS84 bounding box to DAYMET LCC projection coordinates."""
    corners = [
        (bbox["west"], bbox["south"]),  # SW
        (bbox["east"], bbox["north"]),  # NE
    ]
    lcc_coords = []
    for lon, lat in corners:
        result = subprocess.run(
            ["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", DAYMET_LCC_PROJ],
            input=f"{lon} {lat}\n", capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return None
        parts = result.stdout.strip().split()
        lcc_coords.append((float(parts[0]), float(parts[1])))
    return {"x_min": lcc_coords[0][0], "y_min": lcc_coords[0][1],
            "x_max": lcc_coords[1][0], "y_max": lcc_coords[1][1]}


def lcc_to_grid_indices(lcc_bbox, buffer_pixels=2):
    """Convert LCC coordinates to DAYMET grid indices with buffer."""
    g = DAYMET_GRID
    y_step = (g["y_last"] - g["y_first"]) / (g["y_size"] - 1)  # -1000
    x_step = (g["x_last"] - g["x_first"]) / (g["x_size"] - 1)  # +1000

    # y is inverted: north=0, south=8074
    y_start = int((lcc_bbox["y_max"] - g["y_first"]) / y_step)
    y_end = int((lcc_bbox["y_min"] - g["y_first"]) / y_step)
    x_start = int((lcc_bbox["x_min"] - g["x_first"]) / x_step)
    x_end = int((lcc_bbox["x_max"] - g["x_first"]) / x_step)

    # Add buffer
    y_start = max(0, y_start - buffer_pixels)
    y_end = min(g["y_size"] - 1, y_end + buffer_pixels)
    x_start = max(0, x_start - buffer_pixels)
    x_end = min(g["x_size"] - 1, x_end + buffer_pixels)

    return {"y_start": y_start, "y_end": y_end,
            "x_start": x_start, "x_end": x_end}


def opendap_download(collection_id, granule_name, variable, indices, output_path):
    """Download a spatial/temporal subset via OPeNDAP .nc endpoint using curl.

    curl with --netrc handles the Earthdata OAuth redirect chain natively.
    """
    y = f"{indices['y_start']}:1:{indices['y_end']}"
    x = f"{indices['x_start']}:1:{indices['x_end']}"

    base = f"{OPENDAP_BASE}/{collection_id}/granules/{granule_name}"
    # Request the variable subset + coordinate arrays
    # URL-encode brackets: [ = %5B, ] = %5D
    constraint = (
        f"{variable}%5B0:1:364%5D%5B{y}%5D%5B{x}%5D,"
        f"y%5B{y}%5D,x%5B{x}%5D,time%5B0:1:364%5D"
    )
    url = f"{base}.nc?{constraint}"

    cmd = [
        "curl", "-g", "-s", "-L",
        "-b", os.path.expanduser("~/.urs_cookies"),
        "-c", os.path.expanduser("~/.urs_cookies"),
        "--netrc",
        "-o", output_path,
        "-w", "%{http_code} %{size_download} %{time_total}",
        url,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        return None, result.stderr

    parts = result.stdout.strip().split()
    http_code = int(parts[0])
    size = int(float(parts[1]))
    elapsed = float(parts[2])

    if http_code != 200 or size < 1000:
        return None, f"HTTP {http_code}, {size} bytes"

    return {"http": http_code, "size": size, "elapsed": elapsed}, None


# =============================================================================
# Step 1: Prerequisites Check
# =============================================================================

def check_prerequisites(dem_path, output_dir):
    """Verify tools and paths are available."""
    print_header("Step 1: Prerequisites Check")
    ok = True

    # GDAL CLI
    stdout, err = run_cmd(["gdalinfo", "--version"])
    if stdout:
        print(f"  GDAL: {stdout.strip()}")
    else:
        print(f"  [-] GDAL not found: {err}")
        ok = False

    # Check NetCDF driver
    stdout, _ = run_cmd(["gdalinfo", "--formats"])
    if stdout and "netCDF" in stdout:
        print("  GDAL NetCDF driver: available")
    else:
        print("  [-] GDAL NetCDF driver not available")
        ok = False

    # DEM file
    if os.path.isfile(dem_path):
        print(f"  DEM: {dem_path} (exists)")
    else:
        print(f"  [-] DEM not found: {dem_path}")
        ok = False

    # Earthdata credentials
    username, _ = get_earthdata_credentials()
    if username:
        print(f"  Earthdata Login: {username} (from ~/.netrc)")
    else:
        print("  [-] Earthdata Login: NOT CONFIGURED")
        print("      THREDDS/NCSS downloads require ~/.netrc with:")
        print("        machine urs.earthdata.nasa.gov")
        print("          login YOUR_USERNAME")
        print("          password YOUR_PASSWORD")
        print("      Register: https://urs.earthdata.nasa.gov/users/new")
        # Not fatal — single-pixel API still works

    # Create output directories
    for subdir in ["daily/tmin", "daily/tmax", "daily/prcp", "daily/vp",
                   "monthly/tmin", "monthly/tmax", "monthly/prcp", "monthly/vp",
                   "geotiff"]:
        Path(output_dir, subdir).mkdir(parents=True, exist_ok=True)
    print(f"  Output: {output_dir} (ready)")

    return ok


def extract_dem_info(dem_path):
    """Extract DEM metadata via gdalinfo -json."""
    print_header("Step 1b: DEM Metadata")
    stdout, err = run_cmd(["gdalinfo", "-json", dem_path])
    if not stdout:
        print(f"  [-] gdalinfo failed: {err}")
        return None

    info = json.loads(stdout)
    size = info.get("size", [0, 0])
    print(f"  Size: {size[0]} x {size[1]} pixels")

    # Extract corner coordinates in WGS84
    corners = info.get("wgs84Extent", {}).get("coordinates", [[]])
    if corners and corners[0]:
        lons = [c[0] for c in corners[0]]
        lats = [c[1] for c in corners[0]]
        dem_bbox = {
            "west": min(lons), "east": max(lons),
            "south": min(lats), "north": max(lats),
        }
        print(f"  WGS84 bbox: W={dem_bbox['west']:.4f} S={dem_bbox['south']:.4f} "
              f"E={dem_bbox['east']:.4f} N={dem_bbox['north']:.4f}")
        return dem_bbox

    print("  [-] Could not extract WGS84 extent from DEM")
    return None


# =============================================================================
# Step 2: Probe THREDDS Catalog
# =============================================================================

def test_catalog_probes(year, session=None):
    """Verify THREDDS dataset availability using known filename patterns.

    We use the known DAYMET v4 naming convention rather than probing
    multiple patterns, to avoid triggering Earthdata rate limits.
    The redirect URL from ORNL DAAC confirmed the pattern:
      daymet_v4_daily_na_{var}_{year}.nc
    """
    print_header("Step 2: Filename Discovery")

    results = {}

    # Known filename patterns (confirmed from ORNL DAAC redirect URLs)
    known_patterns = {
        "daily_v4r1": ("daymet_v4_daily_na_tmin_{year}.nc", 2129),
        "daily_v4": ("daymet_v4_daily_na_tmin_{year}.nc", 1840),
        "monthly_v4": ("daymet_v4_monthly_na_tmin_{year}.nc", 1855),
    }

    if session:
        # Only probe the primary dataset to avoid rate limits
        label = "daily_v4r1"
        pattern, dsid = known_patterns[label]
        filename = pattern.format(year=year)
        url = f"{OPENDAP_NCSS_BASE}/{dsid}/{filename}/dataset.xml"
        print(f"  Checking dataset {dsid} ({label})...")
        try:
            resp = session.get(url, timeout=20)
            if resp.status_code == 200:
                print(f"  [+] Dataset {dsid} ({label}): {filename} (confirmed)")
                results[label] = {
                    "status": "available",
                    "filename_pattern": filename,
                    "dataset_id": dsid,
                }
            else:
                print(f"  [-] Dataset {dsid} ({label}): HTTP {resp.status_code}")
                results[label] = {"status": "unavailable", "dataset_id": dsid}
        except requests.RequestException as e:
            print(f"  [-] Dataset {dsid} ({label}): {e}")
            results[label] = {"status": "unavailable", "dataset_id": dsid}
    else:
        print("  No authenticated session — using known filename patterns")

    # Always populate results with known patterns for downstream use
    for label, (pattern, dsid) in known_patterns.items():
        if label not in results:
            filename = pattern.format(year=year)
            results[label] = {
                "status": "assumed",
                "filename_pattern": filename,
                "dataset_id": dsid,
            }
            print(f"  [?] Dataset {dsid} ({label}): {filename} (assumed)")

    return results


# =============================================================================
# Step 3: Single-Pixel API Test
# =============================================================================

def test_single_pixel(bbox, year, output_dir):
    """Test the DAYMET single-pixel API."""
    print_header("Step 3: Single-Pixel API Test")

    center_lat = (bbox["north"] + bbox["south"]) / 2
    center_lon = (bbox["west"] + bbox["east"]) / 2

    params = {
        "lat": center_lat,
        "lon": center_lon,
        "vars": ",".join(DAYMET_VARS),
        "years": str(year),
    }

    print(f"  Center point: lat={center_lat:.4f}, lon={center_lon:.4f}")
    print(f"  URL: {SINGLE_PIXEL_URL}?{'&'.join(f'{k}={v}' for k,v in params.items())}")

    try:
        t0 = time.time()
        resp = requests.get(SINGLE_PIXEL_URL, params=params, timeout=60)
        elapsed = time.time() - t0

        if resp.status_code != 200:
            print_result("Single-pixel API", False, f"HTTP {resp.status_code}")
            print(f"  Response: {resp.text[:300]}")
            return False

        # Save response
        out_path = os.path.join(output_dir, f"single_pixel_{year}.csv")
        with open(out_path, "w") as f:
            f.write(resp.text)

        # Parse and report
        lines = resp.text.strip().split("\n")
        # Skip header lines (lines starting with comments or column names)
        data_lines = [l for l in lines if l and not l.startswith("#") and not l.startswith("year")]
        header_line = None
        for l in lines:
            if l.startswith("year") or ("tmin" in l.lower() and "tmax" in l.lower()):
                header_line = l
                break

        print(f"  Response: {len(lines)} lines, {len(resp.text)} bytes in {elapsed:.1f}s")
        if header_line:
            print(f"  Columns: {header_line.strip()}")
        if data_lines:
            print(f"  Data rows: {len(data_lines)}")
            print(f"  First row: {data_lines[0][:120]}")
            if len(data_lines) > 180:
                print(f"  Mid-year:  {data_lines[181][:120]}")

        print(f"  Saved to: {out_path}")
        print_result("Single-pixel API", True, f"{len(data_lines)} days")
        return True

    except requests.RequestException as e:
        print_result("Single-pixel API", False, str(e))
        return False


# =============================================================================
# Step 4: NCSS Daily Subsetting
# =============================================================================

def test_opendap_daily(bbox, year, output_dir, indices, auth_ok):
    """Download daily DAYMET data via OPeNDAP for each variable."""
    print_header("Step 4: OPeNDAP Daily Download (Daymet_Daily_V4R1)")

    if not auth_ok:
        print("  [-] No Earthdata credentials — skipping OPeNDAP downloads")
        return {var: {"status": "fail", "error": "no auth"} for var in DAYMET_VARS}

    collection_id = CMR_COLLECTIONS["daily"]
    results = {}

    print(f"  Grid indices: y[{indices['y_start']}:{indices['y_end']}] "
          f"x[{indices['x_start']}:{indices['x_end']}]")
    ny = indices["y_end"] - indices["y_start"] + 1
    nx = indices["x_end"] - indices["x_start"] + 1
    print(f"  Subset size: {ny}x{nx} pixels, 365 days")

    for var in DAYMET_VARS:
        print(f"\n  --- {var} ---")
        granule = f"Daymet_Daily_V4R1.daymet_v4_daily_na_{var}_{year}.nc"
        out_path = os.path.join(output_dir, "daily", var, f"{var}_{year}_gg.nc")

        info, err = opendap_download(collection_id, granule, var, indices, out_path)
        if info:
            print(f"  Downloaded: {fmt_size(info['size'])} in {info['elapsed']:.1f}s")
            print(f"  Saved to: {out_path}")
            print_result(f"OPeNDAP daily {var}", True, fmt_size(info["size"]))
            results[var] = {"status": "pass", "path": out_path, "size": info["size"]}
        else:
            print_result(f"OPeNDAP daily {var}", False, err)
            results[var] = {"status": "fail", "error": err}

    return results


# =============================================================================
# Step 5: NCSS Monthly Subsetting
# =============================================================================

def test_opendap_monthly(bbox, year, output_dir, indices, auth_ok):
    """Test monthly DAYMET data via OPeNDAP (probe only, one variable)."""
    print_header("Step 5: OPeNDAP Monthly Probe (Daymet_Monthly_V4R1)")

    if not auth_ok:
        print("  [-] No Earthdata credentials — skipping")
        return {"status": "fail", "error": "no auth"}

    collection_id = CMR_COLLECTIONS["monthly"]
    var = "tmin"
    granule = f"Daymet_Monthly_V4R1.daymet_v4_monthly_na_{var}_{year}.nc"
    out_path = os.path.join(output_dir, "monthly", var,
                           f"{var}_{year}_monthly_gg.nc")

    # Monthly has 12 time steps instead of 365
    monthly_indices = dict(indices)
    y = f"{indices['y_start']}:1:{indices['y_end']}"
    x = f"{indices['x_start']}:1:{indices['x_end']}"

    base = f"{OPENDAP_BASE}/{collection_id}/granules/{granule}"
    constraint = (
        f"{var}%5B0:1:11%5D%5B{y}%5D%5B{x}%5D,"
        f"y%5B{y}%5D,x%5B{x}%5D,time%5B0:1:11%5D"
    )
    url = f"{base}.nc?{constraint}"

    print(f"  Testing with {var}...")
    cmd = [
        "curl", "-g", "-s", "-L",
        "-b", os.path.expanduser("~/.urs_cookies"),
        "-c", os.path.expanduser("~/.urs_cookies"),
        "--netrc",
        "-o", out_path,
        "-w", "%{http_code} %{size_download} %{time_total}",
        url,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    parts = result.stdout.strip().split()
    if len(parts) >= 3:
        http_code = int(parts[0])
        size = int(float(parts[1]))
        elapsed = float(parts[2])
        if http_code == 200 and size > 1000:
            print(f"  Downloaded: {fmt_size(size)} in {elapsed:.1f}s")
            print_result("OPeNDAP monthly", True, f"{granule}")
            return {"status": "pass", "path": out_path}
        else:
            print_result("OPeNDAP monthly", False, f"HTTP {http_code}, {size} bytes")
    else:
        print_result("OPeNDAP monthly", False, "curl error")

    return {"status": "fail"}


# =============================================================================
# Step 6: Legacy Dataset 1840 Check
# =============================================================================

def test_legacy_dataset(year):
    """HEAD request to check if legacy dataset 1840 is still available."""
    print_header("Step 6: Legacy Dataset 1840 (run-workflow compatibility)")

    dataset_id = 1840  # Legacy dataset ID from run-workflow
    patterns = [
        f"daymet_v4_daily_na_tmin_{year}.nc",
        f"daymet_v4_tmin_{year}_na.nc",
    ]

    for pattern in patterns:
        url = f"https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/{dataset_id}/{pattern}"
        print(f"  HEAD {url}")
        try:
            resp = requests.head(url, timeout=15, allow_redirects=True)
            size = resp.headers.get("Content-Length", "unknown")
            ctype = resp.headers.get("Content-Type", "unknown")
            print(f"  Status: {resp.status_code}, Size: {size}, Type: {ctype}")
            if resp.status_code == 200:
                print_result("Legacy 1840", True, f"{pattern}")
                return True
        except requests.RequestException as e:
            print(f"  Error: {e}")

    print_result("Legacy 1840", False, "No working URL pattern found")
    print("  -> run-workflow line 256 uses dataset 1840 with undefined {region}")
    print("  -> Needs update to dataset 2129 with correct filename pattern")
    return False


# =============================================================================
# Step 7: Validate Downloaded NetCDF
# =============================================================================

def validate_netcdf(nc_path, variable):
    """Inspect downloaded NetCDF with gdalinfo."""
    if not os.path.isfile(nc_path):
        return {"status": "missing"}

    # First get subdataset listing
    stdout, err = run_cmd(["gdalinfo", nc_path])
    if not stdout:
        return {"status": "error", "detail": err}

    result = {"status": "pass", "subdatasets": [], "detail": ""}

    # Find subdatasets
    for line in stdout.split("\n"):
        if "SUBDATASET_" in line and "_NAME=" in line:
            sd_name = line.split("=", 1)[1].strip()
            result["subdatasets"].append(sd_name)

    # Inspect the main variable subdataset
    sd_target = None
    for sd in result["subdatasets"]:
        if variable in sd:
            sd_target = sd
            break

    if not sd_target and result["subdatasets"]:
        sd_target = result["subdatasets"][0]

    if sd_target:
        stdout2, _ = run_cmd(["gdalinfo", sd_target])
        if stdout2:
            # Extract key info
            for line in stdout2.split("\n"):
                line = line.strip()
                if line.startswith("Size is"):
                    result["grid_size"] = line
                elif "PROJCRS" in line or "proj=" in line.lower():
                    result["crs"] = line
                elif "Band " in line and "Type=" in line:
                    result["band_info"] = line

            # Count bands (= time steps)
            band_count = stdout2.count("Band ")
            result["band_count"] = band_count
            result["subdataset_used"] = sd_target

    return result


def validate_all_netcdf(daily_results, output_dir):
    """Validate all downloaded daily NetCDF files."""
    print_header("Step 7: NetCDF Validation")

    all_ok = True
    validated = {}

    for var, info in daily_results.items():
        if info.get("status") != "pass":
            continue

        nc_path = info["path"]
        print(f"\n  --- {var}: {os.path.basename(nc_path)} ---")

        vresult = validate_netcdf(nc_path, var)

        if vresult.get("subdatasets"):
            print(f"  Subdatasets: {len(vresult['subdatasets'])}")
            for sd in vresult["subdatasets"][:4]:
                print(f"    {sd}")

        if vresult.get("grid_size"):
            print(f"  {vresult['grid_size']}")
        if vresult.get("band_count"):
            print(f"  Bands (time steps): {vresult['band_count']}")
            expected = 365 if var != "swe" else 365
            if vresult["band_count"] >= 360:
                print_result(f"NetCDF {var}", True,
                           f"{vresult['band_count']} bands")
            else:
                print_result(f"NetCDF {var}", False,
                           f"Expected ~365 bands, got {vresult['band_count']}")
                all_ok = False
        else:
            print_result(f"NetCDF {var}", False, "Could not determine bands")
            all_ok = False

        validated[var] = vresult

    return validated, all_ok


# =============================================================================
# Step 8: Convert NetCDF to GeoTIFF
# =============================================================================

def convert_to_geotiff(nc_path, variable, band, dem_path, output_dir, year, bbox):
    """Convert a single band from NetCDF to GeoTIFF matching DEM CRS."""
    bb = buffered_bbox(bbox)

    # Find the right subdataset name
    stdout, _ = run_cmd(["gdalinfo", nc_path])
    sd_target = None
    if stdout:
        for line in stdout.split("\n"):
            if "SUBDATASET_" in line and "_NAME=" in line and variable in line:
                sd_target = line.split("=", 1)[1].strip()
                break

    if not sd_target:
        sd_target = f"NETCDF:{nc_path}:{variable}"

    out_file = os.path.join(output_dir, "geotiff",
                           f"{variable}_{year}_day{band:03d}.tif")

    cmd = [
        "gdalwarp", "-of", "GTiff",
        "-s_srs", DAYMET_LCC_PROJ,
        "-t_srs", "EPSG:32613",  # UTM Zone 13N
        "-te_srs", "EPSG:4326",
        "-te", str(bb["west"]), str(bb["south"]),
              str(bb["east"]), str(bb["north"]),
        "-r", "bilinear",
        "-b", str(band),
        "-overwrite",
        sd_target,
        out_file,
    ]

    stdout, err = run_cmd(cmd)
    if err and "ERROR" in err.upper():
        return None, err

    if os.path.isfile(out_file):
        return out_file, None
    return None, err or "Output file not created"


def convert_sample_geotiffs(daily_results, dem_path, output_dir, year, bbox):
    """Convert sample days to GeoTIFF for each variable."""
    print_header("Step 8: NetCDF to GeoTIFF Conversion")

    converted = {}

    for var, info in daily_results.items():
        if info.get("status") != "pass":
            continue

        nc_path = info["path"]
        print(f"\n  --- {var} ---")

        for day in SAMPLE_DAYS:
            out_path, err = convert_to_geotiff(
                nc_path, var, day, dem_path, output_dir, year, bbox
            )

            if out_path:
                # Verify output
                stdout, _ = run_cmd(["gdalinfo", "-json", out_path])
                if stdout:
                    ginfo = json.loads(stdout)
                    size = ginfo.get("size", [0, 0])
                    fsize = os.path.getsize(out_path)
                    print(f"  Day {day:3d}: {size[0]}x{size[1]} px, {fmt_size(fsize)}")
                    print(f"           {out_path}")

                    # Check for valid data
                    bands = ginfo.get("bands", [])
                    if bands:
                        binfo = bands[0]
                        vmin = binfo.get("computedMin", binfo.get("minimum", "?"))
                        vmax = binfo.get("computedMax", binfo.get("maximum", "?"))
                        print(f"           Value range: {vmin} to {vmax}")

                print_result(f"GeoTIFF {var} day {day}", True)
                converted.setdefault(var, []).append(out_path)
            else:
                print_result(f"GeoTIFF {var} day {day}", False, err or "unknown error")

    return converted


# =============================================================================
# Step 9: Summary Report
# =============================================================================

def print_summary(single_pixel_ok, daily_results, monthly_result,
                  legacy_ok, validation_ok, converted, output_dir, year):
    """Print final summary report."""
    print_header("SUMMARY REPORT")

    print("\n  Test Results:")
    print(f"  {'Test':<35} {'Status':<8} {'Details'}")
    print(f"  {'-'*35} {'-'*8} {'-'*30}")

    tests = [
        ("Single-pixel API", single_pixel_ok, "daymet.ornl.gov"),
        ("OPeNDAP daily (V4R1)", all(r.get("status") == "pass"
         for r in daily_results.values()), f"{sum(1 for r in daily_results.values() if r.get('status')=='pass')}/{len(DAYMET_VARS)} vars"),
        ("OPeNDAP monthly (V4R1)", monthly_result.get("status") == "pass",
         monthly_result.get("path", monthly_result.get("error", ""))),
        ("Legacy dataset (1840)", legacy_ok, "run-workflow compat"),
        ("NetCDF validation", validation_ok, "band counts"),
        ("GeoTIFF conversion", bool(converted), f"{sum(len(v) for v in converted.values())} files"),
    ]

    for name, passed, detail in tests:
        status = "PASS" if passed else "FAIL"
        print(f"  {name:<35} {status:<8} {detail}")

    # Downloaded files
    print(f"\n  Downloaded files in {output_dir}/:")
    for root, dirs, files in os.walk(output_dir):
        for f in sorted(files):
            fpath = os.path.join(root, f)
            rel = os.path.relpath(fpath, output_dir)
            size = os.path.getsize(fpath)
            print(f"    {rel:<55} {fmt_size(size):>10}")

    # Recommendations for run-workflow fix
    print("\n  Recommendations for eemt/eemt/run-workflow:")
    print(f"  1. Replace THREDDS NCSS with OPeNDAP (opendap.earthdata.nasa.gov)")
    print(f"  2. Use CMR collection C2532426483-ORNL_CLOUD for daily V4R1")
    print(f"  3. Granule pattern: Daymet_Daily_V4R1.daymet_v4_daily_na_{{var}}_{{year}}.nc")
    print(f"  4. Subset via OPeNDAP .nc?{{var}}[time][y][x] (requires .netrc auth)")
    print(f"  5. Update metget.sh to use gdalwarp for LCC->UTM reprojection")

    # Save report
    report_path = os.path.join(output_dir, "validation_report.txt")
    with open(report_path, "w") as f:
        f.write(f"DAYMET API Validation Report — Gordon Gulch — {year}\n")
        f.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        for name, passed, detail in tests:
            f.write(f"{'PASS' if passed else 'FAIL'}: {name} — {detail}\n")
    print(f"\n  Report saved: {report_path}")


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Test DAYMET v4 API access for Gordon Gulch"
    )
    parser.add_argument("--dem", default=DEFAULT_DEM,
                       help="Path to input DEM GeoTIFF")
    parser.add_argument("--year", type=int, default=DEFAULT_YEAR,
                       help="Test year (default: 2020)")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT,
                       help="Output directory for downloaded data")
    parser.add_argument("--skip-download", action="store_true",
                       help="Skip downloads, validate existing files only")
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Verbose output")
    args = parser.parse_args()

    # Resolve DEM path relative to repo root if needed
    dem_path = args.dem
    if not os.path.isabs(dem_path):
        # Try relative to script location, then cwd
        repo_root = Path(__file__).resolve().parent.parent
        candidate = repo_root / dem_path
        if candidate.exists():
            dem_path = str(candidate)

    bbox = GORDON_GULCH_BBOX
    year = args.year
    output_dir = args.output_dir

    print(f"DAYMET v4 API Access Test — Gordon Gulch")
    print(f"Year: {year}")
    print(f"Bbox: W={bbox['west']} S={bbox['south']} E={bbox['east']} N={bbox['north']}")
    print(f"Output: {output_dir}")

    # Step 1: Prerequisites
    if not check_prerequisites(dem_path, output_dir):
        print("\n[-] Prerequisites check failed. Exiting.")
        sys.exit(1)

    dem_bbox = extract_dem_info(dem_path)

    if args.skip_download:
        print("\n  --skip-download: skipping API tests, validating existing files")
        # Build daily_results from existing files
        daily_results = {}
        for var in DAYMET_VARS:
            nc_path = os.path.join(
                output_dir, "daily", var,
                f"daymet_v4_daily_na_{var}_{year}_gordongulch.nc"
            )
            if os.path.isfile(nc_path):
                daily_results[var] = {"status": "pass", "path": nc_path,
                                     "size": os.path.getsize(nc_path)}
            else:
                daily_results[var] = {"status": "missing"}

        validated, validation_ok = validate_all_netcdf(daily_results, output_dir)
        converted = convert_sample_geotiffs(
            daily_results, dem_path, output_dir, year, bbox
        )
        print_summary(False, daily_results, {}, False,
                     validation_ok, converted, output_dir, year)
        return

    # Verify Earthdata credentials
    auth_ok, auth_err = create_earthdata_session()
    if auth_err:
        print(f"\n  Warning: {auth_err}")
        print("  OPeNDAP downloads will be skipped. Single-pixel API will still work.")

    # Step 2: Convert bbox to grid indices
    print_header("Step 2: Compute DAYMET Grid Indices")
    bb = buffered_bbox(bbox)
    lcc = bbox_to_lcc(bb)
    if lcc:
        print(f"  LCC SW: ({lcc['x_min']:.0f}, {lcc['y_min']:.0f})")
        print(f"  LCC NE: ({lcc['x_max']:.0f}, {lcc['y_max']:.0f})")
        indices = lcc_to_grid_indices(lcc)
        ny = indices["y_end"] - indices["y_start"] + 1
        nx = indices["x_end"] - indices["x_start"] + 1
        print(f"  Grid: y[{indices['y_start']}:{indices['y_end']}] "
              f"x[{indices['x_start']}:{indices['x_end']}] ({ny}x{nx} pixels)")
    else:
        print("  [-] Failed to convert bbox to LCC")
        indices = {"y_start": 5228, "y_end": 5236,
                   "x_start": 4110, "x_end": 4118}
        print(f"  Using hardcoded Gordon Gulch indices")

    # Step 3: Single-pixel test
    single_pixel_ok = test_single_pixel(bbox, year, output_dir)

    # Step 4: OPeNDAP daily download
    daily_results = test_opendap_daily(bbox, year, output_dir, indices, auth_ok)

    # Step 5: OPeNDAP monthly probe
    monthly_result = test_opendap_monthly(bbox, year, output_dir, indices, auth_ok)

    # Step 6: Legacy check (informational only)
    legacy_ok = test_legacy_dataset(year)

    # Step 7: Validate NetCDF
    validated, validation_ok = validate_all_netcdf(daily_results, output_dir)

    # Step 8: Convert to GeoTIFF
    converted = convert_sample_geotiffs(
        daily_results, dem_path, output_dir, year, bbox
    )

    # Step 9: Summary
    print_summary(single_pixel_ok, daily_results, monthly_result,
                 legacy_ok, validation_ok, converted, output_dir, year)


if __name__ == "__main__":
    main()
