# EEMT Ubuntu 24.04 Docker Image

Modern Docker image for the Effective Energy and Mass Transfer (EEMT) Algorithm Suite based on Ubuntu 24.04 LTS.

## Features

- **Ubuntu 24.04 LTS** base image
- **Python 3.12** with conda environment management
- **GDAL 3.11** with full geospatial stack
- **GRASS GIS 8.4+** compiled from source with EEMT extensions
- **QGIS LTR** for additional geospatial processing
- **CCTools 7.1.7** for distributed workflow execution
- **Complete Python scientific stack** (numpy, pandas, xarray, etc.)

## Quick Start

### Build the Image

```bash
cd docker/ubuntu/24.04
./build.sh
```

### Run Interactive Shell

```bash
docker run -it --rm eemt/ubuntu24.04:latest
```

### Run EEMT Workflow

```bash
# Mount your data directory and run EEMT
docker run -it --rm -v $(pwd)/data:/data eemt/ubuntu24.04:latest

# Inside container, activate environment and run EEMT
conda activate eemt-gis
cd /data
python /opt/eemt/sol/run-workflow --step 15 --num_threads 4 your_dem.tif
```

## Environment Details

### Conda Environment: `eemt-gis`

The image includes a pre-built conda environment with:

- **Geospatial Core**: GDAL 3.11, PROJ 9+, PDAL 2.8+, GEOS 3.13+
- **Python Scientific**: numpy, pandas, xarray, scipy, matplotlib
- **GIS Python**: rasterio, geopandas, fiona, shapely, pyproj
- **Jupyter**: jupyterlab, ipywidgets, ipyleaflet
- **Climate Data**: netcdf4, zarr, cfgrib

### GRASS GIS Solar Radiation

Built-in GRASS modules for solar radiation modeling:
- `r.sun` - Solar radiation with multi-threaded processing (use `nprocs` parameter)
- `r.sun.hourly` - Hourly solar calculations (addon)
- `r.sun.daily` - Daily solar aggregation (addon)

!!! note "r.sun.mp merged into core r.sun"
    As of GRASS GIS 7.4, the r.sun.mp addon was merged into the core `r.sun` module.
    Use `r.sun ... nprocs=N` for multi-threaded processing.

### Paths and Environment

```bash
# GRASS GIS
export GISBASE=/usr/local/grass84
export PATH=$GISBASE/bin:$PATH

# CCTools
export PATH=/opt/eemt/bin:$PATH

# Conda environment activated by default
conda activate eemt-gis
```

## Development Workflow

### Build with Custom Options

```bash
# Build with specific tag
docker build -t eemt/ubuntu24.04:dev .

# Build with build cache
docker build --cache-from eemt/ubuntu24.04:latest -t eemt/ubuntu24.04:new .
```

### Development Mount

```bash
# Mount EEMT source code for development
docker run -it --rm \
  -v $(pwd)/../../sol:/opt/eemt/sol \
  -v $(pwd)/../../eemt:/opt/eemt/eemt \
  -v $(pwd)/data:/data \
  eemt/ubuntu24.04:latest
```

## Troubleshooting

### Common Issues

1. **GRASS not found**: Ensure `/usr/local/grass84/bin` is in PATH
2. **Python imports fail**: Activate conda environment: `conda activate eemt-gis`
3. **Permission errors**: Check that user `eemt` owns data directories

### Debugging

```bash
# Check GRASS installation
grass --version

# Test Python GRASS interface
python -c "import grass.script as gs; print('GRASS Python OK')"

# Verify GDAL
gdalinfo --version

# Check conda environment
conda list
```

### Performance Tuning

```bash
# Run with more memory
docker run --memory=8g -it eemt/ubuntu24.04:latest

# Use multiple CPUs
docker run --cpus=4 -it eemt/ubuntu24.04:latest

# Mount tmpfs for temporary data
docker run --tmpfs /tmp:rw,noexec,nosuid,size=2g -it eemt/ubuntu24.04:latest
```

## Image Size

The complete image is approximately 3-4 GB and includes:
- Ubuntu 24.04 base (~200 MB)
- System dependencies (~500 MB)
- Miniconda + scientific Python stack (~1.5 GB)
- GRASS GIS compiled from source (~800 MB)
- QGIS and additional tools (~500 MB)

## Security

- Runs as non-root user `eemt`
- Minimal attack surface with only required packages
- Regular security updates via Ubuntu 24.04 LTS
- No unnecessary network services exposed