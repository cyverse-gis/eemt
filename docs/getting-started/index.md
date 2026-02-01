---
title: Getting Started
---

# Getting Started with EEMT

## Overview

This guide will help you set up the EEMT calculation environment and run your first analysis. EEMT calculations require topographic data, climate data, and specialized GIS software.

## System Requirements

### Minimum Hardware
- **CPU**: 4 cores (8+ recommended for parallel processing)
- **RAM**: 8 GB (16+ GB recommended for large datasets)
- **Storage**: 50 GB free space (more for large study areas)
- **GPU**: Optional but recommended for r.sun calculations

### Software Dependencies

#### Core GIS Stack
```bash
# Ubuntu/Debian installation
sudo apt update
sudo apt install grass grass-dev gdal-bin python3-gdal python3-rasterio

# macOS (via Homebrew)
brew install grass gdal python

# Windows: Use OSGeo4W installer or Conda
conda install -c conda-forge grass gdal rasterio
```

#### Python Environment
```bash
# Create virtual environment
python3 -m venv eemt-env
source eemt-env/bin/activate  # Linux/macOS
# eemt-env\Scripts\activate   # Windows

# Install required packages
pip install -r requirements.txt
```

#### Required Python Packages
```
numpy>=1.24
pandas>=2.0
xarray>=2024.1
rasterio>=1.3
geopandas>=0.14
matplotlib>=3.7
scipy>=1.11
requests>=2.28
```

## Core Concepts

### EEMT Components

**Effective Energy and Mass Transfer** quantifies energy flux to the Critical Zone:

```
EEMT = E_BIO + E_PPT [MJ m⁻² yr⁻¹]
```

#### Biological Energy (E_BIO)
- Energy from photosynthesis and primary production
- Calculated from Net Primary Production (NPP)
- **Formula**: `E_BIO = NPP × 22 MJ/kg`

#### Precipitation Energy (E_PPT)  
- Thermal energy from effective precipitation
- Water available for subsurface processes
- **Formula**: `E_PPT = F × c_w × ΔT`
  - F = effective precipitation flux [kg m⁻² s⁻¹]
  - c_w = specific heat of water [4.18 × 10³ J kg⁻¹ K⁻¹]
  - ΔT = temperature difference from 273.15K

### Calculation Approaches

#### 1. Traditional EEMT (EEMT_TRAD)
- Uses simple climate averages
- No topographic or vegetation effects
- Good for regional comparisons

#### 2. Topographic EEMT (EEMT_TOPO)  
- Incorporates slope, aspect, and solar radiation
- Mass-conservative water redistribution
- Accounts for local microclimates

#### 3. Vegetation EEMT (EEMT_TOPO-VEG)
- Adds vegetation structure effects
- Uses Leaf Area Index (LAI) and canopy height
- Most accurate for site-specific analyses

## Basic Workflow

### Step 1: Prepare Input Data

#### Digital Elevation Model (DEM)
```bash
# Download USGS 3DEP data (example for Arizona)
wget "https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/SRTMGL1/SRTMGL1_srtm.zip"

# Or use OpenTopography API
curl -X GET "https://portal.opentopography.org/API/globaldem" \
  -G -d "demtype=SRTMGL1" \
  -d "south=32.0" -d "north=32.5" \
  -d "west=-111.0" -d "east=-110.5" \
  -d "outputFormat=GTiff"
```

#### Climate Data
```bash
# DAYMET data (automated download in workflow)
# Or manual download from ORNL DAAC
# https://daymet.ornl.gov/
```

### Step 2: Set Up GRASS GIS Environment

```bash
# Create new GRASS location from DEM
grass -c your_dem.tif ~/grassdata/eemt_project/PERMANENT

# Verify projection
g.proj -p

# Set computational region  
g.region raster=your_dem -p
```

### Step 3: Run Solar Radiation Analysis

```bash
# Basic solar radiation for single day
r.sun elevation=dem day=180 glob_rad=solar_jun29

# Multi-day parallel processing
python sol/run-workflow --step 15 --num_threads 4 your_dem.tif
```

### Step 4: Calculate EEMT

#### Simple EEMT Calculation
```python
import numpy as np
import rasterio

# Load required data
with rasterio.open('solar_annual.tif') as src:
    solar_radiation = src.read(1)
    
with rasterio.open('precipitation.tif') as src:
    precipitation = src.read(1)
    
with rasterio.open('temperature.tif') as src:
    temperature = src.read(1)

# Calculate NPP (simplified)
npp = 3000 * (1 - np.exp(1.315 - 0.119 * temperature))  # kg/m²/yr
npp[precipitation <= 0] = 0  # No production without water

# Calculate energy components
e_bio = npp * 22e6 / (365 * 24 * 3600)  # Convert to W/m²
e_ppt = precipitation * 4180 * (temperature - 273.15) / (365 * 24 * 3600)
e_ppt[e_ppt < 0] = 0  # No energy below freezing

# Calculate EEMT
eemt = e_bio + e_ppt  # W/m²
eemt_annual = eemt * 365 * 24 * 3600 / 1e6  # MJ/m²/yr
```

#### Using the EEMT Workflow
```bash
# Full EEMT calculation with topography
cd eemt/
python run-workflow --start-year 2015 --end-year 2020 \
  --step 15 --num_threads 8 \
  --output eemt_results/ \
  your_dem.tif
```

## Validation and Quality Control

### Check Input Data Quality

```python
# Verify DEM characteristics
import rasterio
with rasterio.open('dem.tif') as src:
    print(f"Projection: {src.crs}")
    print(f"Resolution: {src.res}")
    print(f"Bounds: {src.bounds}")
    print(f"Data type: {src.dtypes[0]}")
```

### Validate EEMT Results

```python
# Check EEMT value ranges
eemt_stats = {
    'min': np.nanmin(eemt_annual),
    'max': np.nanmax(eemt_annual), 
    'mean': np.nanmean(eemt_annual),
    'std': np.nanstd(eemt_annual)
}

print(f"EEMT range: {eemt_stats['min']:.1f} - {eemt_stats['max']:.1f} MJ/m²/yr")

# Expected ranges by climate zone:
# Arid: 5-15 MJ/m²/yr
# Semiarid: 15-25 MJ/m²/yr  
# Humid: 25-50 MJ/m²/yr
```

## Common Issues and Solutions

### Memory Issues
```bash
# Process large DEMs in tiles
gdal_retile.py -ps 1000 1000 -targetDir tiles/ large_dem.tif

# Or use chunked processing with Dask
import dask.array as da
dem_chunked = da.from_array(dem, chunks=(1000, 1000))
```

### Projection Problems  
```bash
# Reproject DEM to match climate data
gdalwarp -t_srs EPSG:4326 input_dem.tif output_dem.tif

# Check coordinate reference systems
gdalinfo dem.tif | grep -i "coordinate system"
```

### Missing Climate Data
```bash
# Download DAYMET data programmatically
python scripts/download_daymet.py --bbox -111.0,32.0,-110.5,32.5 \
  --years 2015-2020 --variables tmin,tmax,prcp
```

## Next Steps

Once you have basic EEMT calculations working:

1. **[Data Sources Guide](../data-sources/index.md)** - Access higher resolution data
2. **[GRASS GIS Tutorials](../grass-gis/index.md)** - Advanced terrain analysis
3. **[Workflow Examples](../examples/index.md)** - Real-world case studies
4. **[API Reference](../api-reference/index.md)** - Function documentation

## Performance Optimization

### Parallel Processing
- Use `--num_threads` parameter for CPU cores
- Enable GPU acceleration for r.sun when available  
- Process multiple years simultaneously

### Memory Management
- Tile large datasets with `gdal_retile.py`
- Use compressed GeoTIFF outputs (`-co COMPRESS=LZW`)
- Monitor memory usage with `htop` or Task Manager

### Storage Optimization  
- Use Cloud-Optimized GeoTIFF (COG) format
- Compress intermediate files
- Clean up temporary GRASS locations

---

*For detailed technical information, see the [scientific background](../background/index.md) and [API documentation](../api-reference/index.md).*