# rsun: GPU-Accelerated Solar Radiation in Rust

**Date**: 2026-03-22
**Status**: Design
**Author**: Claude Code + tswetnam

## Problem

The EEMT solar radiation workflow uses GRASS GIS `r.sun` via shell scripts, spawning 378 separate processes per resolution (1 prep + 365 daily + 12 monthly). Each process creates a temporary GRASS location, imports rasters, computes radiation, exports results, and cleans up. At 0.5 m resolution (51.4M cells), a single annual run takes ~380 CPU-hours. Multi-resolution analysis across 6 surfaces (10m, 5m, 2m, 1m, 0.5m DTM, 0.5m DSM) totals ~885 CPU-hours.

**Note**: The existing `MONTH_DAYS` table in `sol/sol/run-workflow` has a bug — day 151 (May 31) is skipped (May ends at day 150, June starts at 152). The new `rsun` tool will fix this by correctly processing all days 1-365 (or 1-366 for leap years). This means monthly sums will differ slightly from legacy output; the legacy bug should not be replicated.

GPU acceleration can reduce this by 40-100x by:
1. Eliminating per-task GRASS GIS overhead (location creation, raster import/export)
2. Parallelizing the per-pixel radiation computation across thousands of GPU cores
3. Batching all 365 days in a single process with the DEM resident in GPU memory

## Solution

A new Rust crate `rsun` that reimplements the GRASS `r.sun` algorithm (~2,800 lines of C) with wgpu compute shaders for cross-vendor GPU support (NVIDIA, AMD, Intel, Apple).

### r.sun Algorithm Summary

The GRASS r.sun source ([OSGeo/grass/raster/r.sun](https://github.com/OSGeo/grass/tree/main/raster/r.sun)) implements the ESRA clear-sky solar radiation model (Hofierka & Suri 2002). The core computation per pixel per time step:

1. **Solar position** (`com_par`): Compute solar altitude and azimuth from latitude, longitude, declination, and hour angle
2. **Shadow check** (`lumcline2` + `searching`): Either ray-march across the DEM to detect terrain shadows, or look up pre-computed horizon angles
3. **Beam radiation** (`brad`): Direct radiation attenuated by atmosphere (Linke turbidity, optical air mass, refraction correction)
4. **Diffuse radiation** (`drad`): Sky-scattered radiation using the Suri/Hofierka clear-sky model with sky view factor
5. **Reflected radiation** (in `drad`): Ground-reflected component using albedo and terrain view factor
6. **Time integration** (`joules2`): Loop from sunrise to sunset at `step` intervals, accumulating radiation and insolation hours

The existing C code uses OpenMP for row-level parallelism (`#pragma omp parallel for` over columns within each row). An experimental OpenCL path exists but is incomplete.

## Architecture

```
rsun/ (Rust workspace)
├── rsun-core/        # Pure Rust solar math (CPU reference, no GPU dependency)
│   ├── solar.rs      # Solar position, declination, sunrise/sunset
│   ├── radiation.rs  # brad(), drad() — beam, diffuse, reflected radiation
│   ├── horizon.rs    # Horizon angle computation (CPU reference)
│   ├── terrain.rs    # Slope/aspect from DEM (CPU reference)
│   └── io.rs         # GeoTIFF I/O via gdal crate
│
├── rsun-gpu/         # wgpu compute shader acceleration
│   ├── context.rs    # GPU device/queue/adapter management
│   ├── shaders/
│   │   ├── horizon.wgsl    # Horizon angle pre-computation kernel
│   │   ├── radiation.wgsl  # Per-pixel radiation kernel (beam+diffuse+reflected)
│   │   └── shadow.wgsl     # Real-time ray-marching shadow kernel
│   ├── buffers.rs    # GPU buffer lifecycle (DEM, slope, aspect, outputs)
│   └── pipeline.rs   # Two-pass orchestration, multi-day batching
│
├── rsun-cli/         # CLI binary
│   └── main.rs       # clap argument parsing, GeoTIFF I/O, GPU dispatch
│
├── rsun-py/          # Python bindings via PyO3 + maturin
│   └── lib.rs        # rsun.compute_day(), rsun.compute_year()
│
└── rsun-wasm/        # WebAssembly target for browser demos via WebGPU (small DEMs only)
    └── lib.rs        # wasm-bindgen exports (limited to ~1M cells by browser buffer limits)
```

### Design Decisions

- **rsun-core has zero GPU dependencies** — runs on any CPU, serves as reference implementation and automatic fallback
- **rsun-gpu depends only on wgpu** — auto-detects GPU at runtime via `wgpu::Instance::request_adapter()`
- **Single-invocation year processing** — loads DEM once, keeps it in GPU memory, runs all 365 days. Eliminates Makeflow DAG entirely for single-machine GPU execution
- **wgpu over CUDA/OpenCL** — wgpu provides Vulkan (NVIDIA/AMD/Intel), Metal (Apple), D3D12 (Windows), and WebGPU (browser) backends from a single codebase. Compute shaders written in WGSL
- **f32 precision on GPU** — matches GRASS r.sun's use of `float` (FCELL) for raster data. CPU reference uses f64 for validation. The radiation accumulation loop (sunrise to sunset) performs ~100-170 f32 additions per pixel per day; Kahan compensated summation will be used in the WGSL shader if initial validation shows accumulated rounding error exceeds 0.1%

## GPU Compute Pipeline

### Pass 1: Horizon Pre-computation (run once per DEM)

```
Input:  DEM grid [rows x cols] as f32 texture/buffer on GPU
Output: horizon_angles [rows x cols x N_directions] as u8 buffer on GPU

For each pixel (i, j), for each direction d in [0, N_directions):
  azimuth = d * (2*pi / N_directions)
  max_angle = 0.0
  step along azimuth:
    dx = step_distance * cos(azimuth)
    dy = step_distance * sin(azimuth)
    sample DEM at (i + dx, j + dy) via bilinear interpolation
    angle = atan2(z_sample - z_local, distance)
    max_angle = max(max_angle, angle)
  horizon_angles[i][j][d] = quantize_f16(max_angle)  // f16 half-float via WGSL `enable f16`
```

**Workgroup**: 8x8 pixels (64 threads per workgroup)
**Dispatch**: `ceil(cols/8) x ceil(rows/8)` workgroups, iterated over `N_directions` (default 36)

This pass runs once per DEM and the results are reused for all 365 days.

### Pass 2: Radiation Calculation (run once per day)

```
Input:  DEM, slope, aspect (f32 buffers), horizon_angles (u8 buffer),
        uniforms: {day, step, linke, albedo, solar_constant, declination}
Output: glob_rad [rows x cols] (f32), insol_time [rows x cols] (f32)

For each pixel (i, j):
  latitude, longitude = project_to_latlon(i, j, geotransform)
  sunrise, sunset = compute_sun_times(latitude, declination)

  glob_rad = 0.0
  insol_time = 0.0

  for time_angle from sunrise to sunset step (step * HOURANGLE):
    solar_alt, solar_azimuth = compute_solar_position(time_angle, latitude, declination)

    if solar_alt > 0:
      // Shadow check via horizon lookup
      horizon_height = interpolate_horizon(horizon_angles, solar_azimuth, N_directions)
      is_shadowed = (horizon_height > solar_alt)

      // Beam radiation (brad)
      if !is_shadowed:
        s0 = cos_incidence_angle(slope, aspect, solar_alt, solar_azimuth)
        if s0 > 0:
          beam = brad(s0, solar_alt, elevation, linke, cbh, G_norm_extra)
          glob_rad += step * beam
          insol_time += step

      // Diffuse radiation (drad) — always computed when sun is up
      diffuse, reflected = drad(s0, beam_h, solar_alt, slope, aspect, linke, albedo)
      glob_rad += step * (diffuse + reflected)
```

**Workgroup**: 8x8 pixels (64 threads)
**Dispatch**: `ceil(cols/8) x ceil(rows/8)` workgroups

### Multi-Day Batching

```
1. Load DEM → GPU buffer (once)
2. Compute slope + aspect on GPU (once, or accept pre-computed)
3. Compute horizon angles on GPU (once, Pass 1)
4. For day in 1..365:
     a. Update day uniform
     b. Dispatch radiation kernel (Pass 2)
     c. Read back glob_rad + insol_time buffers → write GeoTIFF
5. Compute monthly sums on GPU via reduction kernel
6. Read back monthly sums → write GeoTIFFs
```

Steps 4a-4c are the inner loop. The DEM, slope, aspect, and horizon data remain in GPU memory throughout.

### NoData Handling

DEM pixels with NoData (NaN or sentinel values) must be explicitly masked in GPU buffers. A separate u8 validity mask buffer is uploaded alongside the DEM. All compute shaders check the validity mask before reading elevation — NoData pixels produce NoData output without affecting neighboring computations. The ray-march shadow kernel treats NoData pixels as transparent (non-blocking).

### Coordinate Transformation

DEMs are typically in projected coordinates (UTM, State Plane, etc.) but solar position requires geographic coordinates (latitude/longitude). The `rsun-core::io` module pre-computes a latitude/longitude grid from the DEM's CRS and geotransform using the `proj` Rust crate, then uploads it as GPU buffers alongside the DEM. For lat/lon projections, no transformation is needed.

### Ray-Marching Mode (Alternative Shadow)

When `--shadow-mode ray-march` is specified (or when GPU VRAM is too small for horizon arrays):

- Skip Pass 1 entirely
- In Pass 2, replace the horizon lookup with real-time ray-marching per pixel per time step
- The `searching()` function from r.sun walks along the sun's azimuth, checking elevation at each step
- More memory-efficient (no horizon array) but computationally heavier per time step
- Useful for single-day or few-day computations where horizon pre-computation overhead isn't amortized

### GPU Memory Budget

For Gordon Gulch at 0.5 m (8,680 x 5,920 = 51.4M cells):

| Buffer | Size | Notes |
|--------|------|-------|
| DEM (f32) | 206 MB | Elevation grid |
| Slope (f32) | 206 MB | Pre-computed or computed on GPU |
| Aspect (f32) | 206 MB | Pre-computed or computed on GPU |
| Horizon angles (f16 x 36) | 3,700 MB | 36 directions at 10-degree intervals; f16 for precision at low solar altitudes |
| glob_rad output (f32) | 206 MB | Per-day output |
| insol_time output (f32) | 206 MB | Per-day output |
| **Total** | **~4.7 GB** | Fits in 6+ GB GPU VRAM |

For GPUs with limited VRAM:
- Use ray-marching mode (skip horizon array, saves 3.7 GB → ~1.4 GB total including intermediate buffers)
- Or reduce horizon directions (18 at 20-degree intervals → 1,850 MB)
- Or use u8 quantization instead of f16 (halves horizon buffer to 1,850 MB, at cost of ~0.38-degree precision)
- Or tile the DEM with overlap for horizon computation
- GPU OOM at runtime: detect `wgpu::BufferMapError` and fall back to CPU automatically

## CLI Interface

```bash
# Single day (drop-in replacement for rsun_day.sh)
rsun compute \
  --dem gordongulch_dtm_05m.tif \
  --day 172 --step 5 \
  --linke 3.0 --albedo 0.2 \
  --glob-rad output/global_day_172.tif \
  --insol-time output/insol_day_172.tif \
  --gpu auto

# Full year (replaces entire Makeflow workflow)
rsun compute \
  --dem gordongulch_dtm_05m.tif \
  --day 1-365 --step 5 \
  --linke 3.0 --albedo 0.2 \
  --output-dir output/ \
  --monthly-sums \
  --gpu auto

# Compute slope/aspect from DEM
rsun terrain \
  --dem gordongulch_dtm_05m.tif \
  --slope-out slope_dec.tif \
  --aspect-out aspect_dec.tif

# Pre-compute horizon angles (optional, for reuse)
rsun horizon \
  --dem gordongulch_dtm_05m.tif \
  --directions 36 \
  --output horizon_angles.bin \
  --gpu auto

# System info
rsun info  # List available GPUs, VRAM, recommended settings
```

### Argument Compatibility

The CLI uses short, clean flag names (not replicating GRASS's `--linke_value` convention):

| Flag | Default | Description |
|------|---------|-------------|
| `--dem` | (required) | Input DEM GeoTIFF |
| `--day` | (required) | Single day (`172`), range (`1-365`), or `all` (365 or 366 for leap years) |
| `--step` | `0.5` | Time step in decimal hours |
| `--linke` | `3.0` | Linke turbidity factor |
| `--albedo` | `0.2` | Surface albedo |
| `--gpu` | `auto` | GPU selection: `auto`, `cpu`, device index |
| `--shadow-mode` | `horizon` | `horizon` (pre-computed) or `ray-march` (real-time) |
| `--horizon-directions` | `36` | Number of azimuth directions for horizon pre-computation |
| `--monthly-sums` | `false` | Also output monthly aggregations |
| `--output-dir` | `.` | Directory for output GeoTIFFs |
| `--format` | `gtiff` | Output format: `gtiff`, `cog` (Cloud Optimized GeoTIFF) |
| `--year` | (none) | Calendar year, enables leap year handling (366 days) |

## Python API

```python
import rsun

# Single day computation
result = rsun.compute_day(
    dem="gordongulch_dtm_05m.tif",
    day=172,
    step=5.0,
    linke=3.0,
    albedo=0.2,
    gpu=True
)
# result.glob_rad -> numpy ndarray (f32)
# result.insol_time -> numpy ndarray (f32)
# result.metadata -> dict with geotransform, CRS, etc.
result.save_glob_rad("output/global_day_172.tif")

# Full year — streaming mode (writes each day to disk, does not hold all 365 in memory)
rsun.compute_year(
    dem="gordongulch_dtm_05m.tif",
    step=5.0,
    linke=3.0,
    albedo=0.2,
    monthly_sums=True,
    output_dir="output/",  # required for year — streams to disk
    gpu=True,
    progress=lambda day, total: print(f"{day}/{total}")
)
# Writes: output/global/daily/total_sun_day_1.tif ... total_sun_day_365.tif
# Writes: output/global/monthly/total_sun_jan_sum.tif ... total_sun_dec_sum.tif
# Does NOT hold all 365 daily grids in memory (51.4M cells * 365 * 4 bytes = 73 GB)

# Pre-compute terrain
slope, aspect = rsun.compute_terrain("gordongulch_dtm_05m.tif", gpu=True)

# GPU info
print(rsun.gpu_info())
# {'adapter': 'NVIDIA RTX 4090', 'vram_mb': 24576, 'backend': 'Vulkan'}
```

## EEMT Workflow Integration

### Modified run-workflow

The existing `sol/sol/run-workflow` gains an `--engine` argument:

```python
parser.add_argument('--engine', dest="engine", default="gpu",
                    choices=["gpu", "makeflow"],
                    help="Execution engine: gpu (single process) or makeflow (legacy)")
```

When `--engine gpu`:
- Skip Makeflow DAG generation entirely
- Call `rsun compute --days 1-365 --monthly-sums` as a single subprocess
- Output directory structure matches existing layout (global/daily/, insol/daily/, etc.)

When `--engine makeflow` (legacy):
- Use existing rsun_prep.sh + rsun_day.sh + Makeflow pipeline

### Container Integration

The Docker container (`docker/ubuntu/24.04/Dockerfile`) would add:

```dockerfile
# Install rsun binary
COPY --from=rsun-builder /usr/local/bin/rsun /usr/local/bin/rsun
```

Or build from source in the container if GPU drivers are available at build time.

### Web Interface

The FastAPI web interface (`web-interface/app.py`) can call `rsun` directly via subprocess or via the Python bindings, eliminating the need for Docker-in-Docker workflow container management for GPU-equipped hosts.

## Performance Estimates

### Speedup Projections

| Resolution | Cells | GRASS r.sun (CPU) | rsun (GPU, RTX 4090) | Speedup | Notes |
|-----------|-------|-------------------|---------------------|---------|-------|
| 10 m | ~128K | ~1 hr | ~2 min | ~30x | GPU underutilized; dispatch overhead dominates |
| 5 m | ~510K | ~4 hrs | ~5 min | ~48x | Approaching useful GPU occupancy |
| 2 m | ~3.2M | ~25 hrs | ~15 min | ~100x | Good GPU utilization |
| 1 m | ~12.8M | ~95 hrs | ~45 min | ~127x | Near-peak GPU occupancy |
| 0.5 m DTM | ~51.4M | ~380 hrs | ~3 hrs | ~127x | Full GPU occupancy; memory-bandwidth limited |
| 0.5 m DSM | ~51.4M | ~380 hrs | ~3 hrs | ~127x | Same as DTM |

*Speedup is non-uniform: small DEMs (< 1M cells) underutilize GPU cores and are dominated by dispatch/transfer overhead. Largest speedups at 1M+ cells where GPU occupancy is high. Estimates based on published GPU solar radiation speedups (70x compute + ~2x GRASS overhead elimination).*

### Where the Speedup Comes From

1. **Elimination of GRASS overhead** (~2x): No location creation, raster import/export, temp directory management for 377 tasks
2. **GPU parallelism** (~50-80x): 51.4M pixels processed in parallel vs. OpenMP row parallelism
3. **Multi-day batching** (~1.5x): DEM loaded once, not 365 times
4. **Combined**: ~150x theoretical, ~100-130x practical (limited by GPU memory bandwidth and GeoTIFF I/O)

## Validation

1. **Numerical equivalence**: Run both GRASS r.sun and `rsun` on `sol/examples/mcn_10m.tif` for days 1, 91, 182, 274 (equinoxes + solstices)
2. **Tolerance**: < 0.1% relative difference in glob_rad (f32 GPU vs f64 CPU precision). If exceeded, enable Kahan compensated summation in the radiation accumulation shader
3. **Edge cases**: NULL/nodata pixels (explicit validity mask), steep slopes (>45 degrees), flat terrain, polar latitudes, leap years (366 days)
4. **Full-year comparison**: Run complete 365-day workflow on mcn_10m.tif, compare monthly sums
5. **Performance benchmarks**: Wall-clock time at each resolution, GPU utilization metrics

## Dependencies

### Rust Crates

| Crate | Version | Purpose |
|-------|---------|---------|
| `wgpu` | latest | GPU compute (Vulkan/Metal/D3D12/WebGPU) |
| `gdal` | latest | GeoTIFF I/O |
| `clap` | 4.x | CLI argument parsing |
| `rayon` | latest | CPU parallelism (fallback) |
| `pyo3` | latest | Python bindings |
| `maturin` | latest | Python package build |
| `wasm-bindgen` | latest | WebAssembly bindings |
| `proj` | latest | CRS coordinate transformations (projected → geographic) |
| `naga` | (via wgpu) | WGSL shader compilation |

### System Dependencies

- Vulkan SDK or Metal (for GPU acceleration)
- GDAL library (for GeoTIFF I/O)
- Python 3.11+ (for Python bindings)
- Rust 1.75+ (for workspace, async, WGSL support)

## Implementation Phases

### Phase 1: Core Math + CPU Reference (~1 week)
- `rsun-core`: Port `com_par`, `brad`, `drad`, `lumcline2`, `com_declin` from C to Rust
- GeoTIFF I/O via gdal crate
- CPU reference implementation with rayon parallelism
- Validate against GRASS r.sun on mcn_10m.tif

### Phase 2: GPU Acceleration (~2 weeks)
- `rsun-gpu`: wgpu context management, buffer lifecycle
- WGSL shaders: horizon pre-computation, radiation calculation, ray-marching shadow
- Two-pass pipeline orchestration
- Multi-day batching

### Phase 3: CLI + Integration (~1 week)
- `rsun-cli`: clap-based argument parsing, output formatting
- Integration with `sol/sol/run-workflow` (`--engine gpu`)
- Docker container integration
- Performance benchmarks

### Phase 4: Python Bindings + WebAssembly (~1 week)
- `rsun-py`: PyO3 bindings, maturin build
- `rsun-wasm`: WebAssembly target, WebGPU compute
- Jupyter notebook example

## References

- Hofierka, J., & Suri, M. (2002). The solar radiation model for Open source GIS. *Proceedings of the Open source GIS-GRASS users conference*.
- GRASS r.sun source: https://github.com/OSGeo/grass/tree/main/raster/r.sun
- wgpu documentation: https://wgpu.rs/
- HORAYZON horizon algorithm (100x speedup): https://gmd.copernicus.org/articles/15/6817/2022/
- GPU solar radiation estimation (70x speedup): Applied Energy, 2023
