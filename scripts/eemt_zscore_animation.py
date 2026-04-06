#!/usr/bin/env python3
"""
EEMT Z-Score Animation — Gordon Gulch 1980-2024
=================================================
Computes monthly mean EEMT climatology, then z-scores for each month
of all 45 years. Renders as a GIF animation with magma colormap.

Output: 540 frames (45 years × 12 months) at 3 fps = 3 minute animation.
"""

import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
import matplotlib.cm as cm
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt

# =============================================================================
# Configuration
# =============================================================================

OUTPUT_BASE = Path("/opt/tswetnam/data/gordon_gulch/eemt_smoke_test")
YEARS = list(range(1980, 2025))
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
          "jul", "aug", "sep", "oct", "nov", "dec"]
MONTH_LABELS = ["January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"]

FPS = 3
OUTPUT_W, OUTPUT_H = 1920, 1080  # 1080p
CMAP_NAME = "magma"
ZSCORE_RANGE = (-3.0, 3.0)  # symmetric z-score color range

# ENSO classification for annotation
STRONG_EL_NINO = {1983, 1998, 2016}
EL_NINO = {1983, 1987, 1988, 1992, 1995, 1998, 2003, 2005, 2007,
           2010, 2015, 2016, 2019, 2024}
STRONG_LA_NINA = {1989, 1999, 2000, 2008, 2011}
LA_NINA = {1984, 1985, 1989, 1996, 1999, 2000, 2001, 2006, 2008,
           2009, 2011, 2012, 2018, 2021, 2022, 2023}


# =============================================================================
# Raster I/O
# =============================================================================

def read_raster(path):
    """Read a GeoTIFF into a numpy float32 array."""
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        # Get dimensions
        result = subprocess.run(
            ["gdalinfo", "-json", path],
            capture_output=True, text=True, timeout=30,
        )
        info = __import__("json").loads(result.stdout)
        cols, rows = info["size"]

        subprocess.run(
            ["gdal_translate", "-of", "ENVI", "-ot", "Float32", "-q", path, tmp_path],
            capture_output=True, timeout=30,
        )
        data = np.fromfile(tmp_path, dtype=np.float32).reshape(rows, cols)
        return data
    finally:
        for ext in ["", ".hdr", ".aux.xml"]:
            p = tmp_path + ext if ext else tmp_path
            if os.path.exists(p):
                os.remove(p)


# =============================================================================
# Compute Climatology and Z-Scores
# =============================================================================

def compute_monthly_climatology(years):
    """Load all EEMT_Trad monthly rasters, compute mean and std per month."""
    print("Computing monthly climatology...")

    # First pass: determine shape from first available file
    shape = None
    for year in years:
        path = OUTPUT_BASE / str(year) / "eemt" / f"EEMT_Trad_jan_{year}.tif"
        if path.exists():
            arr = read_raster(str(path))
            shape = arr.shape
            break
    if shape is None:
        print("ERROR: No EEMT rasters found")
        sys.exit(1)

    rows, cols = shape
    print(f"  Raster shape: {cols}x{rows}")

    # Load all data: (45, 12, rows, cols)
    all_data = np.full((len(years), 12, rows, cols), np.nan, dtype=np.float32)

    for yi, year in enumerate(years):
        for mi, month in enumerate(MONTHS):
            path = OUTPUT_BASE / str(year) / "eemt" / f"EEMT_Trad_{month}_{year}.tif"
            if path.exists():
                arr = read_raster(str(path))
                # Replace nodata with NaN
                arr[arr < -9000] = np.nan
                all_data[yi, mi] = arr
        if (yi + 1) % 10 == 0:
            print(f"  Loaded {yi + 1}/{len(years)} years")

    print(f"  Loaded {len(years)} years")

    # Compute per-month climatology (mean and std across years)
    # Shape: (12, rows, cols)
    with np.errstate(all="ignore"):
        monthly_mean = np.nanmean(all_data, axis=0)  # (12, rows, cols)
        monthly_std = np.nanstd(all_data, axis=0)     # (12, rows, cols)

    # Compute z-scores for every year/month
    # z = (value - mean) / std
    monthly_std_safe = np.where(monthly_std > 0.001, monthly_std, np.nan)
    zscores = (all_data - monthly_mean[np.newaxis, :, :, :]) / monthly_std_safe[np.newaxis, :, :, :]

    # Clip extreme z-scores
    zscores = np.clip(zscores, -5, 5)

    # Create valid mask from first non-NaN year
    valid_mask = np.isfinite(monthly_mean[0])

    return all_data, monthly_mean, monthly_std, zscores, valid_mask


# =============================================================================
# Rendering
# =============================================================================

def make_colorbar_image(vmin, vmax, label, cmap_name=CMAP_NAME):
    """Render a vertical colorbar as a numpy BGR image."""
    fig, ax = plt.subplots(figsize=(1.0, 6), dpi=100)
    norm = mcolors.Normalize(vmin=vmin, vmax=vmax)
    sm = plt.cm.ScalarMappable(cmap=cmap_name, norm=norm)
    sm.set_array([])
    cbar = fig.colorbar(sm, cax=ax, orientation="vertical")
    cbar.set_label(label, fontsize=12, color="white")
    cbar.ax.tick_params(colors="white", labelsize=10)

    fig.patch.set_facecolor("black")
    fig.tight_layout(pad=0.5)

    fig.canvas.draw()
    buf = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8)
    w, h = fig.canvas.get_width_height()
    img = buf.reshape(h, w, 4)[:, :, :3]  # drop alpha
    plt.close(fig)
    return cv2.cvtColor(img, cv2.COLOR_RGB2BGR)


def put_text(frame, text, pos, font_scale=1.0, thickness=2, color=(255, 255, 255)):
    """Draw white text with black outline."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    # Outline
    cv2.putText(frame, text, pos, font, font_scale, (0, 0, 0), thickness + 2, cv2.LINE_AA)
    # Fill
    cv2.putText(frame, text, pos, font, font_scale, color, thickness, cv2.LINE_AA)


def render_frame(zscore_2d, valid_mask, year, month_idx, eemt_mean,
                 cmap, norm, cbar_img):
    """Render a single z-score frame as a BGR image at OUTPUT_W x OUTPUT_H."""
    rows, cols = zscore_2d.shape

    # Normalize and apply colormap
    arr = zscore_2d.copy()
    arr[~valid_mask] = np.nan
    arr_norm = norm(arr)
    arr_norm = np.clip(arr_norm, 0, 1)

    colored = cmap(arr_norm)
    colored[~np.isfinite(zscore_2d) | ~valid_mask] = [0, 0, 0, 1]

    rgb = (colored[:, :, :3] * 255).astype(np.uint8)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)

    # Resize to output dimensions, preserving aspect ratio
    margin_top, margin_bottom, margin_left, margin_right = 70, 60, 20, 160
    avail_w = OUTPUT_W - margin_left - margin_right
    avail_h = OUTPUT_H - margin_top - margin_bottom

    aspect = cols / rows
    if avail_w / avail_h > aspect:
        # Height-limited
        map_h = avail_h
        map_w = int(map_h * aspect)
    else:
        # Width-limited
        map_w = avail_w
        map_h = int(map_w / aspect)

    frame = np.zeros((OUTPUT_H, OUTPUT_W, 3), dtype=np.uint8)
    resized = cv2.resize(bgr, (map_w, map_h), interpolation=cv2.INTER_NEAREST)
    y_start = margin_top + (avail_h - map_h) // 2
    x_start = margin_left + (avail_w - map_w) // 2
    frame[y_start:y_start + map_h, x_start:x_start + map_w] = resized

    # Overlay colorbar on right side
    cb_h, cb_w = cbar_img.shape[:2]
    y_off = (OUTPUT_H - cb_h) // 2
    x_off = OUTPUT_W - cb_w - 10
    if y_off >= 0 and x_off >= 0:
        frame[y_off:y_off + cb_h, x_off:x_off + cb_w] = cbar_img

    # Title
    put_text(frame, "EEMT Z-Score — Gordon Gulch", (20, 45), font_scale=1.2, thickness=2)

    # Date and year
    month_label = MONTH_LABELS[month_idx]
    put_text(frame, f"{month_label} {year}", (20, OUTPUT_H - 30),
             font_scale=1.5, thickness=3)

    # ENSO badge
    if year in STRONG_EL_NINO:
        enso_text = "STRONG EL NINO"
        enso_color = (0, 80, 255)  # red-orange BGR
    elif year in EL_NINO:
        enso_text = "El Nino"
        enso_color = (0, 140, 255)
    elif year in STRONG_LA_NINA:
        enso_text = "STRONG LA NINA"
        enso_color = (255, 180, 0)  # blue BGR
    elif year in LA_NINA:
        enso_text = "La Nina"
        enso_color = (255, 200, 80)
    else:
        enso_text = ""
        enso_color = (200, 200, 200)

    if enso_text:
        put_text(frame, enso_text, (400, OUTPUT_H - 30),
                 font_scale=1.0, thickness=2, color=enso_color)

    # Mean EEMT value
    put_text(frame, f"Mean EEMT: {eemt_mean:.2f} MJ/m\u00b2",
             (OUTPUT_W - 400, 45), font_scale=0.8, thickness=2)

    return frame


# =============================================================================
# Animation
# =============================================================================

def create_animation(all_data, zscores, valid_mask, years):
    """Create GIF animation of monthly z-scores across all years."""
    print("\nRendering animation...")

    cmap = cm.magma
    norm = mcolors.Normalize(vmin=ZSCORE_RANGE[0], vmax=ZSCORE_RANGE[1])
    cbar_img = make_colorbar_image(ZSCORE_RANGE[0], ZSCORE_RANGE[1], "Z-Score (σ)")

    # Use ffmpeg to create GIF via PNG frames
    frame_dir = tempfile.mkdtemp(prefix="eemt_frames_")
    total_frames = len(years) * 12
    frame_num = 0

    for yi, year in enumerate(years):
        for mi in range(12):
            zscore_2d = zscores[yi, mi]
            eemt_mean = np.nanmean(all_data[yi, mi][valid_mask])
            if not np.isfinite(eemt_mean):
                eemt_mean = 0.0

            frame = render_frame(zscore_2d, valid_mask, year, mi, eemt_mean,
                                cmap, norm, cbar_img)

            frame_path = os.path.join(frame_dir, f"frame_{frame_num:04d}.png")
            cv2.imwrite(frame_path, frame)
            frame_num += 1

        if (yi + 1) % 10 == 0 or yi == len(years) - 1:
            print(f"  Rendered {yi + 1}/{len(years)} years ({frame_num} frames)")

    # Create GIF using ffmpeg with magma palette
    gif_path = str(OUTPUT_BASE / "eemt_zscore_1980_2024.gif")
    mp4_path = str(OUTPUT_BASE / "eemt_zscore_1980_2024.mp4")

    print(f"\n  Encoding GIF ({total_frames} frames at {FPS} fps)...")
    # First generate a palette for high-quality GIF
    palette_path = os.path.join(frame_dir, "palette.png")
    subprocess.run([
        "ffmpeg", "-y", "-framerate", str(FPS),
        "-i", os.path.join(frame_dir, "frame_%04d.png"),
        "-vf", f"fps={FPS},scale={OUTPUT_W}:-1:flags=lanczos,palettegen=stats_mode=diff",
        palette_path,
    ], capture_output=True, timeout=120)

    subprocess.run([
        "ffmpeg", "-y", "-framerate", str(FPS),
        "-i", os.path.join(frame_dir, "frame_%04d.png"),
        "-i", palette_path,
        "-lavfi", f"fps={FPS},scale={OUTPUT_W}:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5",
        gif_path,
    ], capture_output=True, timeout=300)

    # Also create MP4 (much smaller, better quality)
    print(f"  Encoding MP4...")
    subprocess.run([
        "ffmpeg", "-y", "-framerate", str(FPS),
        "-i", os.path.join(frame_dir, "frame_%04d.png"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-crf", "18", "-preset", "medium",
        mp4_path,
    ], capture_output=True, timeout=120)

    # Cleanup frames
    import shutil
    shutil.rmtree(frame_dir, ignore_errors=True)

    # Report sizes
    for path, label in [(gif_path, "GIF"), (mp4_path, "MP4")]:
        if os.path.exists(path):
            size_mb = os.path.getsize(path) / (1024 * 1024)
            print(f"  {label}: {path} ({size_mb:.1f} MB)")

    return gif_path, mp4_path


# =============================================================================
# Main
# =============================================================================

def main():
    print("EEMT Z-Score Animation — Gordon Gulch 1980-2024")
    print("=" * 55)
    t0 = time.time()

    # Step 1: Compute climatology and z-scores
    all_data, monthly_mean, monthly_std, zscores, valid_mask = \
        compute_monthly_climatology(YEARS)

    # Print climatology summary
    print("\nMonthly Climatology (spatial mean):")
    print(f"  {'Month':<10} {'Mean':>8} {'Std':>8}")
    for mi in range(12):
        m = np.nanmean(monthly_mean[mi][valid_mask])
        s = np.nanmean(monthly_std[mi][valid_mask])
        print(f"  {MONTH_LABELS[mi]:<10} {m:>8.2f} {s:>8.2f}")

    # Step 2: Create animation
    gif_path, mp4_path = create_animation(all_data, zscores, valid_mask, YEARS)

    elapsed = time.time() - t0
    print(f"\nCompleted in {elapsed:.0f}s")


if __name__ == "__main__":
    main()
