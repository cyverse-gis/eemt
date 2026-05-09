#!/usr/bin/env python3
"""
Download DAYMET v4 R1 daily climate data for Pinaleño + Santa Teresa Mts.

Variables: tmin, tmax, prcp, vp
Source: NASA Earthdata OPeNDAP (requires ~/.netrc with urs.earthdata.nasa.gov)

Usage:
    python download_pinaleno_daymet.py
    python download_pinaleno_daymet.py --start-year 1980 --end-year 2024
    python download_pinaleno_daymet.py --year 2020
"""

import argparse
import os
import subprocess
import time

PINALENO_BBOX = {
    "north": 33.15,
    "south": 32.50,
    "east": -109.75,
    "west": -110.40,
}

BBOX_BUFFER = 0.02

DAYMET_VARS = ["tmin", "tmax", "prcp", "vp"]

DAYMET_LCC_PROJ = (
    "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 "
    "+x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
)

OPENDAP_BASE = "https://opendap.earthdata.nasa.gov/collections"
CMR_DAILY_COLLECTION = "C2532426483-ORNL_CLOUD"

DAYMET_GRID = {
    "y_first": 4984000.0,
    "y_last": -3090000.0,
    "y_size": 8075,
    "x_first": -4560250.0,
    "x_last": 3251750.0,
    "x_size": 7814,
    "step": 1000.0,
}

OUTPUT_BASE = "/opt/tswetnam/pinaleno/daymet/daily"


def bbox_to_lcc(bbox):
    buffered = {
        "north": bbox["north"] + BBOX_BUFFER,
        "south": bbox["south"] - BBOX_BUFFER,
        "east": bbox["east"] + BBOX_BUFFER,
        "west": bbox["west"] - BBOX_BUFFER,
    }
    corners = [
        (buffered["west"], buffered["south"]),
        (buffered["east"], buffered["north"]),
    ]
    lcc_coords = []
    for lon, lat in corners:
        result = subprocess.run(
            ["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", DAYMET_LCC_PROJ],
            input=f"{lon} {lat}\n", capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            raise RuntimeError(f"gdaltransform failed: {result.stderr}")
        parts = result.stdout.strip().split()
        lcc_coords.append((float(parts[0]), float(parts[1])))
    return {"x_min": lcc_coords[0][0], "y_min": lcc_coords[0][1],
            "x_max": lcc_coords[1][0], "y_max": lcc_coords[1][1]}


def lcc_to_grid_indices(lcc_bbox, buffer_pixels=2):
    g = DAYMET_GRID
    y_step = (g["y_last"] - g["y_first"]) / (g["y_size"] - 1)
    x_step = (g["x_last"] - g["x_first"]) / (g["x_size"] - 1)
    y_start = int((lcc_bbox["y_max"] - g["y_first"]) / y_step)
    y_end = int((lcc_bbox["y_min"] - g["y_first"]) / y_step)
    x_start = int((lcc_bbox["x_min"] - g["x_first"]) / x_step)
    x_end = int((lcc_bbox["x_max"] - g["x_first"]) / x_step)
    y_start = max(0, y_start - buffer_pixels)
    y_end = min(g["y_size"] - 1, y_end + buffer_pixels)
    x_start = max(0, x_start - buffer_pixels)
    x_end = min(g["x_size"] - 1, x_end + buffer_pixels)
    return {"y_start": y_start, "y_end": y_end,
            "x_start": x_start, "x_end": x_end}


def opendap_download(variable, year, indices, output_path):
    granule = f"Daymet_Daily_V4R1.daymet_v4_daily_na_{variable}_{year}.nc"
    y = f"{indices['y_start']}:1:{indices['y_end']}"
    x = f"{indices['x_start']}:1:{indices['x_end']}"
    base = f"{OPENDAP_BASE}/{CMR_DAILY_COLLECTION}/granules/{granule}"
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
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        return None, result.stderr
    parts = result.stdout.strip().split()
    if len(parts) < 3:
        return None, "curl output parse error"
    http_code = int(parts[0])
    size = int(float(parts[1]))
    elapsed = float(parts[2])
    if http_code != 200 or size < 1000:
        return None, f"HTTP {http_code}, {size} bytes"
    return {"http": http_code, "size": size, "elapsed": elapsed}, None


def fmt_size(nbytes):
    for unit in ["B", "KB", "MB", "GB"]:
        if nbytes < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} TB"


def main():
    parser = argparse.ArgumentParser(description="Download DAYMET for Pinaleño Mts")
    parser.add_argument("--year", type=int, help="Single year to download")
    parser.add_argument("--start-year", type=int, default=1980)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--output-dir", default=OUTPUT_BASE)
    args = parser.parse_args()

    years = [args.year] if args.year else list(range(args.start_year, args.end_year + 1))

    print("DAYMET Download — Pinaleño + Santa Teresa Mts")
    print("=" * 60)
    print(f"Bbox: W={PINALENO_BBOX['west']} S={PINALENO_BBOX['south']} "
          f"E={PINALENO_BBOX['east']} N={PINALENO_BBOX['north']}")
    print(f"Years: {years[0]}-{years[-1]} ({len(years)} years)")
    print(f"Variables: {', '.join(DAYMET_VARS)}")

    print("\nComputing DAYMET grid indices...")
    lcc_bbox = bbox_to_lcc(PINALENO_BBOX)
    print(f"  LCC bbox: x=[{lcc_bbox['x_min']:.0f}, {lcc_bbox['x_max']:.0f}] "
          f"y=[{lcc_bbox['y_min']:.0f}, {lcc_bbox['y_max']:.0f}]")
    indices = lcc_to_grid_indices(lcc_bbox)
    ny = indices["y_end"] - indices["y_start"] + 1
    nx = indices["x_end"] - indices["x_start"] + 1
    print(f"  Grid indices: y[{indices['y_start']}:{indices['y_end']}] "
          f"x[{indices['x_start']}:{indices['x_end']}]")
    print(f"  Subset size: {ny}x{nx} pixels ({ny}km x {nx}km)")

    for var in DAYMET_VARS:
        os.makedirs(os.path.join(args.output_dir, var), exist_ok=True)

    total_files = len(years) * len(DAYMET_VARS)
    completed = 0
    failed = 0
    t0 = time.time()
    for year in years:
        for var in DAYMET_VARS:
            out_path = os.path.join(args.output_dir, var, f"{var}_{year}_pinaleno.nc")
            if os.path.isfile(out_path) and os.path.getsize(out_path) > 1000:
                completed += 1
                continue
            info, err = opendap_download(var, year, indices, out_path)
            completed += 1
            if info:
                print(f"  [{completed}/{total_files}] {var}_{year}: "
                      f"{fmt_size(info['size'])} in {info['elapsed']:.1f}s")
            else:
                failed += 1
                print(f"  [{completed}/{total_files}] {var}_{year}: FAILED - {err}")

    elapsed = time.time() - t0
    print(f"\nCompleted: {completed - failed}/{total_files} files in {elapsed:.0f}s")
    if failed:
        print(f"Failed: {failed} files")
    print(f"Output: {args.output_dir}")


if __name__ == "__main__":
    main()
