# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Effective Energy and Mass Transfer (EEMT)** - Geospatial modeling toolkit for calculating energy flux in the Critical Zone. Combines topographic solar radiation (GRASS GIS r.sun) with DAYMET climate data to model soil formation, landscape evolution, and energy balance.

**Languages**: Python 3.11 (CCTools compatibility), Bash (GRASS wrappers)

## Architecture

The system has two independent workflow pipelines and a web frontend that orchestrates them via Docker containers:

```
Web Interface (FastAPI :5000)
    └── Docker Container (eemt:ubuntu24.04)
            ├── Solar Workflow (sol/sol/) → Makeflow local batch
            └── EEMT Workflow (eemt/eemt/) → Makeflow + Work Queue
```

### Two-Pipeline Design
- **Solar pipeline** (`sol/sol/run-workflow`): Generates a Makeflow file with 365 daily r.sun tasks + 12 monthly aggregations. Runs in **local batch mode** (`makeflow --batch-type=local`).
- **EEMT pipeline** (`eemt/eemt/run-workflow`): Extends solar with DAYMET climate integration. Runs in **Work Queue mode** (`makeflow --batch-type=wq`) requiring `~/.eemt-makeflow-password`.

Both `run-workflow` scripts are Python-based Makeflow generators (not direct executors). They write `.mf` workflow definition files, then invoke `makeflow` to execute them.

### Web Interface
- `web-interface/app.py` - FastAPI with SQLite job tracking (`/tmp/jobs.db`), async job execution, progress streaming via "PROGRESS:", "STATUS:", "COMPLETED:", "ERROR:" markers
- `web-interface/containers/workflow_manager.py` - Docker orchestration with triple fallback (subprocess CLI → Python SDK → socket → mock mode). Supports LOCAL, MASTER, WORKER node types.
- Two-stage file upload: file uploaded first (UUID-named), then job submitted referencing stored file

### Container Architecture
- Base image: Ubuntu 24.04 + Miniforge Python 3.11 + GRASS GIS 8.4 (from source) + CCTools 7.15.14
- Container entry points: `docker/ubuntu/24.04/container-scripts/run-solar-workflow.py` and `run-eemt-workflow.py`
- Web interface container extends base with FastAPI/uvicorn

### GRASS GIS Integration
Each workflow task creates a temporary GRASS location, runs r.sun or r.series, exports results as GeoTIFF, then cleans up. Shell scripts (`rsun.sh`, `rsum.sh`, `reemt.sh`, `metget.sh`, `twi.sh`) are copied to the output directory for task isolation - this is a Makeflow requirement.

## Build & Run Commands

```bash
# Docker Compose (recommended) - starts web interface on :5000
docker-compose up

# Build base container manually
cd docker/ubuntu/24.04/ && ./build.sh

# Run web interface without Docker Compose
cd web-interface/ && pip install -r requirements.txt && python app.py

# Build and serve docs locally (uses Zensical, not plain mkdocs)
pip install zensical pymdown-extensions && zensical build

# Test solar workflow directly in container
docker run --rm \
  -v $(pwd)/sol/examples:/data/input:ro \
  -v $(pwd)/test-output:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py \
  --dem /data/input/mcn_10m.tif \
  --output /data/output \
  --step 15 --num-threads 2 --job-id test-001

# Verify outputs: 365 daily files + 12 monthly sums
ls test-output/global/daily/total_sun_day_*.tif | wc -l    # 365
ls test-output/global/monthly/total_sun_*_sum.tif | wc -l  # 12

# Legacy direct execution (requires host GRASS + CCTools)
cd sol/sol/ && python run-workflow --step 15 --num_threads 2 ../examples/mcn_10m.tif

# Distributed execution (Work Queue)
python scripts/start-master.py   # Start master node
python scripts/start-worker.py   # Start worker node (connects to master)

# Linting and testing (dev dependencies in root requirements.txt)
black --check .
flake8 .
mypy .
pytest
```

## Requirements Files

- `requirements.txt` (root) — Zensical docs build + scientific computing libraries + dev tools (pytest, black, flake8, mypy)
- `web-interface/requirements.txt` — FastAPI, uvicorn, docker SDK, psutil for the web app

## CI/CD

Only GitHub Pages deployment exists (`.github/workflows/ghpages.yml`). No automated Docker image builds - containers are built locally. Docs deploy on push to `master` or `2026_update` using `zensical build`.

## Key Parameters

| Parameter | Range | Description |
|-----------|-------|-------------|
| `step` | 3-15 min | Solar calculation time interval (lower = more accurate, slower) |
| `linke_value` | 1.0-8.0 | Atmospheric turbidity |
| `albedo_value` | 0.0-1.0 | Surface reflectance |
| `num_threads` | 1-512 | Parallel Makeflow tasks |
| `start_year/end_year` | 1980-present | DAYMET temporal range (EEMT only) |

## Data Flow

1. User uploads GeoTIFF DEM via web interface or mounts as Docker volume
2. `run-workflow` parses DEM metadata (projection, bounds, resolution) via `Tiff.py`/`parser.py`
3. Generates Makeflow `.mf` file defining task DAG
4. Makeflow executes shell script tasks (each creates temp GRASS location)
5. Solar: 365 daily GeoTIFFs → 12 monthly aggregations
6. EEMT: Downloads DAYMET data via ORNL DAAC API → combines with solar → EEMT products

**Climate data source**: `https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/1840/`

## Common Gotchas

- **Password file**: EEMT workflow requires `~/.eemt-makeflow-password` for Work Queue mode
- **Solar vs EEMT batch modes**: Solar uses `--batch-type=local`, EEMT uses `--batch-type=wq` - they are not interchangeable
- **Python 3.11 not 3.12**: CCTools requires 3.11; the Dockerfile uses Miniforge to pin this
- **GRASS from source**: The container builds GRASS 8.4 from source (`install_grass.sh`), not from packages
- **Duplicate Tiff.py/parser.py**: `sol/sol/` and `eemt/eemt/` each have their own copies - changes must be synchronized
- **Docker socket required**: Web interface needs `/var/run/docker.sock` mounted to manage workflow containers
- **No GPU acceleration**: Referenced in some docs but not implemented

## Docker Compose Profiles

- Default: `eemt-web` only (local execution)
- `distributed`: Adds `eemt-master` + `eemt-worker` services (Work Queue on port 9123)
- `docs`: Adds Zensical/MkDocs doc server on port 8000
- `cleanup`: Adds cron-based job cleanup service (daily at 2 AM)

## Code Style

- **Python**: PEP 8, type hints
- **Bash**: Use `set -e` for error handling
- **Comments**: Explain scientific rationale, not just implementation

## Commit Convention

Use prefix tags: `FIX:`, `FEATURE:`, `REFACTOR:`, `UPDATE:`, `DOCS:`, `CLEANUP:`, `MODERNIZE:`

Commit after each logical change. Include which files changed and why. If workflow scripts or Dockerfiles changed, note whether container rebuild is needed.
