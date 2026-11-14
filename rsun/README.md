# rsun — Rust Solar Radiation Toolkit

A Rust port of [GRASS GIS r.sun](https://grass.osgeo.org/grass-stable/manuals/r.sun.html), the ESRA clear-sky solar radiation model (Hofierka & Suri, 2002). Computes global solar radiation and sunshine duration on arbitrary terrain from a Digital Elevation Model (DEM).

## Overview

`rsun` implements the same algorithms as GRASS `rsunlib.c`, producing pixel-compatible output validated against the original (see [Validation](#validation)). Every core equation has been formally verified in Lean 4 — see [Formal Verification](#formal-verification).

**Key advantages over GRASS r.sun:**

- **Parallel by default** — Rayon auto-parallelism over all pixels
- **GPU acceleration** — wgpu compute shaders (Vulkan/Metal/DX12/WebGPU) via `rsun-gpu`
- **Multi-target** — CLI binary, Python wheel, WebAssembly module
- **No GRASS dependency** — standalone binary reads/writes GeoTIFF directly

## Architecture

Five-crate Cargo workspace:

```
rsun/
├── rsun-core/     CPU reference library (solar, radiation, horizon, terrain, I/O)
├── rsun-cli/      Command-line binary with compute/terrain/info subcommands
├── rsun-gpu/      GPU acceleration via wgpu compute shaders (WGSL)
├── rsun-py/       Python bindings via PyO3 + maturin (numpy arrays)
└── rsun-wasm/     WebAssembly module for browser demos (CPU-only, <1M pixels)
```

### Core Modules (`rsun-core/src/`)

| Module | Purpose |
|--------|---------|
| `solar.rs` | Declination, sunrise/sunset, solar position, hour angle |
| `radiation.rs` | Beam (direct), diffuse, reflected radiation; cos incidence (Jenco) |
| `horizon.rs` | Ray-marching horizon angle computation, azimuthal interpolation |
| `terrain.rs` | Slope/aspect from DEM via Horn's method |
| `io.rs` | GeoTIFF read/write via GDAL, coordinate reprojection (behind `io` feature) |
| `types.rs` | `Grid`, `SolarParams`, `DayResult`, `GeoTransform` |

## Build Instructions

### Prerequisites

- Rust 1.75+ (`rustup` recommended)
- GDAL development libraries (for CLI and `io` feature)

### CLI Binary

```bash
cargo build --release --bin rsun
```

The binary is at `target/release/rsun`.

### Core Library Only (no GDAL)

```bash
cargo build -p rsun-core
```

### Python Wheel

Requires Python 3.8+ and [maturin](https://www.maturin.rs/):

```bash
cd rsun-py
pip install maturin
maturin develop --release
```

### WebAssembly

Requires [wasm-pack](https://rustwasm.github.io/wasm-pack/):

```bash
wasm-pack build --target web rsun-wasm
```

## Usage

### CLI — Compute Solar Radiation

```bash
# Single day (summer solstice)
rsun compute --dem dem.tif --day 172 \
    --glob-rad glob_rad_172.tif --insol-time insol_172.tif

# Full year (writes to output directory)
rsun compute --dem dem.tif --day all --output-dir results/

# Day range with custom parameters
rsun compute --dem dem.tif --day 1-90 \
    --step 0.25 --linke 2.5 --albedo 0.3 --output-dir results/

# Force CPU mode (skip GPU detection)
rsun compute --dem dem.tif --day 172 --gpu cpu \
    --glob-rad output.tif
```

### CLI — Terrain Analysis

```bash
rsun terrain --dem dem.tif --slope-out slope.tif --aspect-out aspect.tif
```

### CLI — GPU Info

```bash
rsun info
```

### Python

```python
import rsun
import numpy as np

# From file (requires GDAL)
result = rsun.compute_day_from_file("dem.tif", day=172)
print(f"Mean radiation: {np.nanmean(result.glob_rad):.1f} Wh/m²")

# From numpy arrays
dem = np.random.uniform(2000, 3000, (100, 100)).astype(np.float32)
slope = np.zeros_like(dem)
aspect = np.zeros_like(dem)
lat = np.full_like(dem, np.radians(40.0))
lon = np.full_like(dem, np.radians(-105.0))

result = rsun.compute_day(dem, slope, aspect, lat, lon, day=172)
print(result.glob_rad.shape)   # (100, 100)
print(result.insol_time.shape) # (100, 100)

# Terrain computation
slope, aspect = rsun.compute_terrain(dem, ew_res=10.0, ns_res=10.0)

# GPU availability
gpus = rsun.gpu_info()
print(gpus)
```

### WebAssembly (JavaScript)

```javascript
import init, { compute_day, declination, sunrise_sunset } from './rsun_wasm.js';

await init();

// Flat 50x50 DEM at 2500m elevation, latitude 40°N
const dem = new Float32Array(2500).fill(2500.0);
const result = compute_day(dem, 50, 50, 0.6981, -1.8326, 172, 0.5);

console.log(`Day ${result.day}: mean radiation = ${mean(result.glob_rad)} Wh/m²`);
```

## Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `day` | — | 1–366 | Day of year |
| `step` | 0.5 | 0.05–1.0 | Time step [hours]; smaller = more accurate |
| `linke` | 3.0 | 1.0–8.0 | Linke turbidity factor (atmospheric clarity) |
| `albedo` | 0.2 | 0.0–1.0 | Surface reflectance |
| `solar_constant` | 1367.0 | — | Extraterrestrial irradiance [W/m²] |

## Validation

The `validation/compare.sh` script compares rsun output pixel-by-pixel against GRASS r.sun on the `mcn_10m.tif` test DEM for 4 representative days (winter/spring/summer/fall):

```bash
cd rsun && bash validation/compare.sh
```

**Acceptance criteria:** Max relative error < 5% per pixel.

Output format:

```
Day    rsun_mean   grass_mean   RMSE        MaxRelErr%  Status
  1      1234.5      1238.2       12.3          3.21      PASS
 91      3456.7      3462.1        8.7          2.54      PASS
172      5678.9      5684.3        6.2          1.87      PASS
274      2345.6      2350.1       10.1          2.98      PASS
```

## Formal Verification

The mathematical equations used in rsun have been formally verified using the [Lean 4](https://lean-lang.org/) theorem prover. The proofs are at `lean4-verification/EEMTVerify/Solar/` and cover:

| Lean 4 File | Verified Properties |
|-------------|-------------------|
| `Declination.lean` | Declination bounded to ±23.44°; day angle monotonicity |
| `SolarConstant.lean` | Eccentricity factor ∈ [0.967, 1.033]; corrected constant ∈ [1321, 1413] W/m² |
| `SunriseSunset.lean` | Sunrise + sunset = 24h; day length ∈ [0, 24]; equinox = 12h |
| `SolarPosition.lean` | Solar altitude ∈ [-π/2, π/2]; noon altitude is daily maximum |
| `AirMass.lean` | Beam transmittance ∈ (0, 1]; elevation correction positive and decreasing |
| `BeamRadiation.lean` | Beam ≥ 0; beam = 0 when surface faces away or at night; beam ≤ G_ext |
| `DiffuseRadiation.lean` | Sky + terrain view factors = 1; reflected = 0 on flat ground |
| `CosIncidence.lean` | \|cos(incidence)\| ≤ 1; flat surface reduces to sin(altitude) |
| `TotalRadiation.lean` | Daily radiation ≥ 0; insolation ≤ day length |

Additionally, `rsun-core/tests/lean4_validation_tests.rs` contains ~23 unit tests that verify the Rust implementation produces values within these Lean 4-proven bounds.

## Testing

```bash
# Core tests (solar, radiation, terrain, horizon, I/O, integration)
cargo test -p rsun-core

# Lean 4 validation tests only
cargo test -p rsun-core -- lean4

# GPU tests (requires GPU)
cargo test -p rsun-gpu

# All workspace tests
cargo test
```

### Test Modules

| Module | Tests |
|--------|-------|
| `rsun-core/tests/solar_tests.rs` | Declination, solar constant, sunrise/sunset, solar position |
| `rsun-core/tests/radiation_tests.rs` | Beam, diffuse, reflected radiation |
| `rsun-core/tests/terrain_tests.rs` | Slope/aspect via Horn's method |
| `rsun-core/tests/horizon_tests.rs` | Horizon angle computation and interpolation |
| `rsun-core/tests/io_tests.rs` | GeoTIFF read/write round-trip |
| `rsun-core/tests/integration_tests.rs` | Full-day computation on synthetic DEMs |
| `rsun-core/tests/lean4_validation_tests.rs` | Lean 4 proven bounds validation |
| `rsun-gpu/tests/` | GPU vs CPU comparison, buffer management, benchmarks |

## References

- Hofierka, J. & Suri, M. (2002). The solar radiation model for Open Source GIS: implementation and applications. *Proceedings of the Open Source GIS - GRASS Users Conference*.
- Spencer, J.W. (1971). Fourier series representation of the position of the Sun. *Search*, 2(5), 172.
- Kasten, F. & Young, A.T. (1989). Revised optical air mass tables and approximation formula. *Applied Optics*, 28(22), 4735–4738.
- Jenco, M. (1992). Distribution of direct solar radiation on georelief and its modelling by means of complex digital model of terrain. *Geograficky Casopis*, 44, 342–355.

## License

GPL-2.0-or-later (consistent with GRASS GIS)
