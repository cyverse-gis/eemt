---
title: Data Preparation Guide
description: Comprehensive guide for preparing input data for EEMT calculations
---

# Data Preparation Guide

## Overview

Proper data preparation is crucial for accurate EEMT calculations. This guide covers all aspects of preparing Digital Elevation Models (DEMs), acquiring climate data, and processing vegetation datasets for EEMT analysis.

## Table of Contents

1. [DEM Preparation](#dem-preparation)
2. [Climate Data Acquisition](#climate-data-acquisition)
3. [Vegetation Data Processing](#vegetation-data-processing)
4. [Quality Control](#quality-control)
5. [Advanced Techniques](#advanced-techniques)

## DEM Preparation

### Data Sources

#### Free Global DEMs

| Dataset | Resolution | Coverage | Best For | Access |
|---------|------------|----------|----------|--------|
| **SRTM** | 30m | 60°N to 56°S | Global studies | [USGS EarthExplorer](https://earthexplorer.usgs.gov/) |
| **ASTER GDEM** | 30m | 83°N to 83°S | Complete global coverage | [NASA Earthdata](https://search.earthdata.nasa.gov/) |
| **ALOS PALSAR** | 12.5m | Global | Higher resolution needs | [ASF DAAC](https://search.asf.alaska.edu/) |
| **FABDEM** | 30m | Global | Vegetation-corrected | [University of Bristol](https://data.bris.ac.uk/data/dataset/s5hqmjcdj8yo2ibzi9b4ew3sn) |

#### Regional High-Resolution DEMs

| Region | Dataset | Resolution | Access |
|--------|---------|------------|--------|
| **USA** | 3DEP | 1m, 3m, 10m | [USGS National Map](https://apps.nationalmap.gov/downloader/) |
| **Europe** | EU-DEM | 25m | [Copernicus](https://land.copernicus.eu/imagery-in-situ/eu-dem) |
| **Canada** | CDEM | 20m | [Open Canada](https://open.canada.ca/data/en/dataset/7f245e4d-76c2-4caa-951a-45d1d2051333) |
| **Australia** | DEM-H | 5m | [Geoscience Australia](https://elevation.fsdf.org.au/) |

### Step 1: Download DEM Data

#### Using GDAL to Access Cloud-Optimized GeoTIFFs

```bash
# Access USGS 3DEP data directly (no download needed)
gdal_translate \
  /vsicurl/https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/CA_SanDiego_2016/TIFF/USGS_1M_CA_SanDiego_2016.tif \
  -projwin -117.0 32.5 -116.5 32.0 \
  study_area_dem.tif

# Access SRTM data via AWS
gdal_translate \
  /vsizip//vsicurl/https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/SRTM_GL1/SRTM_GL1_srtm/North_America/N32W117.hgt.zip/N32W117.hgt \
  srtm_tile.tif
```

#### Using Python for Automated Download

```python
#!/usr/bin/env python3
"""
Automated DEM download for study area
"""

import requests
import rasterio
from rasterio.merge import merge
from pathlib import Path
import numpy as np

def download_3dep_dem(bbox, resolution='10m', output_file='dem.tif'):
    """
    Download USGS 3DEP DEM for bounding box
    
    Parameters:
    bbox: [west, south, east, north] in decimal degrees
    resolution: '1m', '3m', '10m', or '30m'
    output_file: Output filename
    """
    
    # USGS 3DEP WCS endpoint
    wcs_url = "https://elevation.nationalmap.gov/arcgis/services/3DEPElevation/ImageServer/WCSServer"
    
    # Build WCS request
    params = {
        'service': 'WCS',
        'version': '2.0.1',
        'request': 'GetCoverage',
        'coverageId': f'DEP3Elevation:{resolution}',
        'format': 'image/tiff',
        'subset': f'x({bbox[0]},{bbox[2]})',
        'subset': f'y({bbox[1]},{bbox[3]})',
        'subsettingCRS': 'EPSG:4326'
    }
    
    # Download DEM
    response = requests.get(wcs_url, params=params, stream=True)
    
    if response.status_code == 200:
        with open(output_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        print(f"DEM downloaded: {output_file}")
        return output_file
    else:
        print(f"Error downloading DEM: {response.status_code}")
        return None

def download_srtm_tiles(bbox, output_file='srtm_merged.tif'):
    """
    Download and merge SRTM tiles for study area
    """
    
    # Calculate required tiles
    west, south, east, north = bbox
    
    # SRTM tiles are 1x1 degree
    lat_tiles = range(int(south), int(north) + 1)
    lon_tiles = range(int(west), int(east) + 1)
    
    tile_files = []
    
    for lat in lat_tiles:
        for lon in lon_tiles:
            # Determine tile name
            ns = 'N' if lat >= 0 else 'S'
            ew = 'E' if lon >= 0 else 'W'
            tile_name = f"{ns}{abs(lat):02d}{ew}{abs(lon):03d}"
            
            # Download from OpenTopography
            url = f"https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/SRTM_GL1/SRTM_GL1_srtm/North_America/{tile_name}.hgt"
            
            tile_file = f"{tile_name}.tif"
            
            # Convert HGT to GeoTIFF
            gdal_command = f"gdal_translate /vsicurl/{url} {tile_file}"
            os.system(gdal_command)
            
            if Path(tile_file).exists():
                tile_files.append(tile_file)
    
    # Merge tiles
    if tile_files:
        datasets = [rasterio.open(f) for f in tile_files]
        merged, transform = merge(datasets)
        
        # Save merged DEM
        profile = datasets[0].profile.copy()
        profile.update({
            'height': merged.shape[1],
            'width': merged.shape[2],
            'transform': transform
        })
        
        with rasterio.open(output_file, 'w', **profile) as dst:
            dst.write(merged[0], 1)
        
        # Cleanup
        for ds in datasets:
            ds.close()
        for f in tile_files:
            Path(f).unlink()
        
        print(f"Merged SRTM DEM: {output_file}")
        return output_file
    
    return None
```

### Step 2: Preprocess DEM

#### Projection and Resampling

```bash
# Check DEM projection
gdalinfo input_dem.tif | grep -A 3 "Coordinate System"

# Reproject to appropriate UTM zone
# Find UTM zone for center of study area
utm_zone=$(gdal_query.py -lon -117.0 -lat 32.5 -utm)

# Reproject DEM
gdalwarp \
  -t_srs "+proj=utm +zone=${utm_zone} +datum=WGS84" \
  -r bilinear \
  -tr 10 10 \
  input_dem.tif \
  dem_utm.tif

# Alternative: Use local projected system (e.g., State Plane)
gdalwarp -t_srs EPSG:2230 input_dem.tif dem_stateplane.tif
```

#### Resolution Optimization

```python
def optimize_dem_resolution(dem_file, target_cells=1000000):
    """
    Resample DEM to optimal resolution for processing
    
    Target ~1 million cells for efficient processing
    """
    
    with rasterio.open(dem_file) as src:
        current_cells = src.width * src.height
        
        if current_cells > target_cells:
            # Calculate resampling factor
            scale_factor = np.sqrt(target_cells / current_cells)
            
            # New resolution
            new_res = src.res[0] / scale_factor
            
            print(f"Current cells: {current_cells:,}")
            print(f"Resampling from {src.res[0]}m to {new_res:.1f}m")
            
            # Resample using GDAL
            output_file = dem_file.replace('.tif', '_resampled.tif')
            
            os.system(f"""
                gdalwarp \
                  -tr {new_res} {new_res} \
                  -r bilinear \
                  {dem_file} \
                  {output_file}
            """)
            
            return output_file
    
    return dem_file
```

### Step 3: Fill Sinks and Pits

Hydrological conditioning ensures proper flow routing:

```python
def fill_sinks(dem_file, output_file='dem_filled.tif'):
    """
    Fill sinks in DEM using GRASS GIS
    """
    
    import grass.script as gs
    
    # Import DEM to GRASS
    gs.run_command('r.in.gdal', input=dem_file, output='dem_raw')
    
    # Fill sinks using r.terraflow
    gs.run_command('r.terraflow',
                   elevation='dem_raw',
                   filled='dem_filled',
                   direction='flow_dir',
                   swatershed='watersheds',
                   accumulation='flow_acc',
                   tci='twi')
    
    # Alternative: Use r.fill.dir for smaller DEMs
    gs.run_command('r.fill.dir',
                   input='dem_raw',
                   output='dem_filled_alt',
                   direction='flow_dir_alt')
    
    # Export filled DEM
    gs.run_command('r.out.gdal',
                   input='dem_filled',
                   output=output_file,
                   format='GTiff',
                   createopt='COMPRESS=LZW')
    
    return output_file

# Alternative using RichDEM (Python)
import richdem as rd

def fill_sinks_richdem(dem_file, output_file='dem_filled.tif'):
    """
    Fill sinks using RichDEM library
    """
    
    # Load DEM
    dem = rd.LoadGDAL(dem_file)
    
    # Fill depressions
    filled = rd.FillDepressions(dem, epsilon=False, in_place=False)
    
    # Save result
    rd.SaveGDAL(output_file, filled)
    
    return output_file
```

### Step 4: Create Analysis Mask

Define your exact study area:

```python
def create_analysis_mask(dem_file, boundary_file, output_file='dem_masked.tif'):
    """
    Clip DEM to study area boundary
    
    Parameters:
    dem_file: Input DEM
    boundary_file: Shapefile or GeoJSON with study area boundary
    output_file: Masked DEM output
    """
    
    import geopandas as gpd
    from rasterio.mask import mask
    
    # Load boundary
    boundary = gpd.read_file(boundary_file)
    
    # Open DEM
    with rasterio.open(dem_file) as src:
        # Reproject boundary if needed
        if boundary.crs != src.crs:
            boundary = boundary.to_crs(src.crs)
        
        # Mask DEM
        out_image, out_transform = mask(src, 
                                        boundary.geometry,
                                        crop=True,
                                        nodata=-9999)
        
        # Update metadata
        out_meta = src.meta.copy()
        out_meta.update({
            'height': out_image.shape[1],
            'width': out_image.shape[2],
            'transform': out_transform,
            'nodata': -9999
        })
        
        # Save masked DEM
        with rasterio.open(output_file, 'w', **out_meta) as dst:
            dst.write(out_image[0], 1)
    
    return output_file
```

## Climate Data Acquisition

### DAYMET Data Download

#### Automated DAYMET Download

```python
def download_daymet_for_dem(dem_file, years, variables=['tmin', 'tmax', 'prcp', 'vp']):
    """
    Download DAYMET data matching DEM extent
    """
    
    import xarray as xr
    from pyproj import Transformer
    
    # Get DEM bounds
    with rasterio.open(dem_file) as src:
        bounds = src.bounds
        
        # Transform to lat/lon if needed
        if src.crs != 'EPSG:4326':
            transformer = Transformer.from_crs(src.crs, 'EPSG:4326', always_xy=True)
            west, south = transformer.transform(bounds.left, bounds.bottom)
            east, north = transformer.transform(bounds.right, bounds.top)
        else:
            west, south, east, north = bounds
    
    # DAYMET API endpoint
    api_url = "https://daymet.ornl.gov/single-pixel/api/data"
    
    climate_data = {}
    
    for year in years:
        for var in variables:
            print(f"Downloading {var} for {year}...")
            
            # Build request
            params = {
                'lat': (south + north) / 2,
                'lon': (west + east) / 2,
                'vars': var,
                'start': f'{year}-01-01',
                'end': f'{year}-12-31',
                'format': 'netcdf'
            }
            
            # For spatial data, use Daymet web service
            spatial_url = f"https://thredds.daac.ornl.gov/thredds/ncss/ornldaac/1840/daymet_v4_daily_na_{var}_{year}.nc"
            
            params_spatial = {
                'var': var,
                'north': north,
                'south': south,
                'east': east,
                'west': west,
                'time_start': f'{year}-01-01T12:00:00Z',
                'time_end': f'{year}-12-31T12:00:00Z',
                'accept': 'netcdf'
            }
            
            response = requests.get(spatial_url, params=params_spatial)
            
            if response.status_code == 200:
                output_file = f'daymet_{var}_{year}.nc'
                with open(output_file, 'wb') as f:
                    f.write(response.content)
                
                climate_data[f'{var}_{year}'] = output_file
    
    return climate_data
```

#### Process DAYMET for EEMT

```python
def process_daymet_for_eemt(daymet_files, dem_file, output_dir='climate_processed'):
    """
    Process DAYMET data to match DEM resolution and projection
    """
    
    Path(output_dir).mkdir(exist_ok=True)
    
    # Load DEM for reference
    with rasterio.open(dem_file) as dem_src:
        dem_profile = dem_src.profile
        dem_bounds = dem_src.bounds
        dem_res = dem_src.res
    
    processed_files = {}
    
    for var_year, nc_file in daymet_files.items():
        print(f"Processing {var_year}...")
        
        # Open NetCDF
        ds = xr.open_dataset(nc_file)
        
        # Get variable name
        var = var_year.split('_')[0]
        
        # Process each day/month
        for time_idx in range(len(ds.time)):
            
            # Extract data for this time
            data = ds[var].isel(time=time_idx)
            
            # Convert to GeoTIFF
            temp_file = f'temp_{var}_{time_idx}.tif'
            
            # Write to temporary GeoTIFF
            # (Implementation depends on DAYMET projection)
            
            # Reproject to match DEM
            output_file = Path(output_dir) / f'{var}_{time_idx:03d}.tif'
            
            gdal_command = f"""
                gdalwarp \
                  -t_srs '{dem_profile['crs']}' \
                  -te {dem_bounds.left} {dem_bounds.bottom} {dem_bounds.right} {dem_bounds.top} \
                  -tr {dem_res[0]} {dem_res[1]} \
                  -r bilinear \
                  {temp_file} \
                  {output_file}
            """
            
            os.system(gdal_command)
            
            processed_files[f'{var}_{time_idx}'] = output_file
    
    return processed_files
```

## Vegetation Data Processing

### NDVI from Satellite Imagery

#### Landsat NDVI Calculation

```python
def calculate_ndvi_landsat(scene_dir, output_file='ndvi.tif'):
    """
    Calculate NDVI from Landsat 8/9 imagery
    """
    
    # Find band files
    red_file = list(Path(scene_dir).glob('*_B4.TIF'))[0]  # Band 4 - Red
    nir_file = list(Path(scene_dir).glob('*_B5.TIF'))[0]  # Band 5 - NIR
    
    # Load bands
    with rasterio.open(red_file) as red_src:
        red = red_src.read(1).astype(float)
        profile = red_src.profile
    
    with rasterio.open(nir_file) as nir_src:
        nir = nir_src.read(1).astype(float)
    
    # Calculate NDVI
    # Avoid division by zero
    denominator = nir + red
    denominator[denominator == 0] = 1
    
    ndvi = (nir - red) / denominator
    
    # Constrain to valid range
    ndvi = np.clip(ndvi, -1, 1)
    
    # Save NDVI
    profile.update(dtype=rasterio.float32, count=1)
    
    with rasterio.open(output_file, 'w', **profile) as dst:
        dst.write(ndvi.astype(np.float32), 1)
    
    return output_file

def download_and_process_sentinel2_ndvi(bbox, date_range, output_file='ndvi_s2.tif'):
    """
    Download and process Sentinel-2 data for NDVI
    Using sentinelsat library
    """
    
    from sentinelsat import SentinelAPI
    from datetime import datetime
    
    # Connect to Copernicus Hub
    api = SentinelAPI('username', 'password', 'https://scihub.copernicus.eu/dhus')
    
    # Search for products
    footprint = f"POLYGON(({bbox[0]} {bbox[1]}, {bbox[2]} {bbox[1]}, {bbox[2]} {bbox[3]}, {bbox[0]} {bbox[3]}, {bbox[0]} {bbox[1]}))"
    
    products = api.query(footprint,
                         date=date_range,
                         platformname='Sentinel-2',
                         cloudcoverpercentage=(0, 20),
                         producttype='S2MSI2A')  # Level-2A (atmospherically corrected)
    
    # Download best product
    if products:
        product_id = list(products.keys())[0]
        api.download(product_id)
        
        # Process downloaded data
        # Extract and calculate NDVI
        # Band 4 (Red) and Band 8 (NIR) for Sentinel-2
        
    return output_file
```

### LAI Estimation

```python
def estimate_lai_from_ndvi(ndvi_file, output_file='lai.tif', method='exponential'):
    """
    Estimate Leaf Area Index from NDVI
    """
    
    with rasterio.open(ndvi_file) as src:
        ndvi = src.read(1)
        profile = src.profile
    
    if method == 'exponential':
        # Exponential relationship (Boegh et al., 2002)
        lai = -2.0 * np.log(1 - ndvi)
        
    elif method == 'polynomial':
        # Polynomial for semiarid (Qi et al., 2000)
        lai = 18.99 * ndvi**3 - 15.24 * ndvi**2 + 6.124 * ndvi - 0.352
        
    elif method == 'linear':
        # Simple linear (for grassland/crops)
        lai = 6.0 * ndvi - 0.5
    
    # Constrain to valid range
    lai = np.clip(lai, 0, 10)
    
    # Handle water/bare soil
    lai[ndvi < 0.1] = 0
    
    # Save LAI
    with rasterio.open(output_file, 'w', **profile) as dst:
        dst.write(lai.astype(np.float32), 1)
    
    return output_file
```

## Quality Control

### DEM Quality Checks

```python
def validate_dem(dem_file):
    """
    Comprehensive DEM quality control
    """
    
    issues = []
    warnings = []
    
    with rasterio.open(dem_file) as src:
        dem = src.read(1)
        
        # Check 1: NoData values
        nodata_count = np.sum(dem == src.nodata) if src.nodata else 0
        nodata_percent = (nodata_count / dem.size) * 100
        
        if nodata_percent > 10:
            warnings.append(f"High NoData percentage: {nodata_percent:.1f}%")
        
        # Check 2: Elevation range
        valid_data = dem[dem != src.nodata] if src.nodata else dem
        
        if len(valid_data) > 0:
            min_elev = np.min(valid_data)
            max_elev = np.max(valid_data)
            
            if min_elev < -500:
                issues.append(f"Unrealistic minimum elevation: {min_elev}m")
            if max_elev > 9000:
                issues.append(f"Unrealistic maximum elevation: {max_elev}m")
            
            # Check 3: Flat areas
            unique_values = np.unique(valid_data)
            if len(unique_values) < 10:
                issues.append("DEM appears to be heavily quantized or flat")
            
        # Check 4: Resolution
        res_x, res_y = src.res
        if abs(res_x - res_y) > 0.001:
            warnings.append(f"Non-square pixels: {res_x} x {res_y}")
        
        # Check 5: Projection
        if not src.crs:
            issues.append("No coordinate system defined")
        elif src.crs.to_epsg() == 4326:
            warnings.append("Geographic coordinates - consider reprojecting")
        
        # Check 6: File size
        size_mb = dem.nbytes / 1024 / 1024
        if size_mb > 500:
            warnings.append(f"Large file size: {size_mb:.1f} MB - consider resampling")
    
    # Report results
    print("=== DEM Validation Report ===")
    
    if not issues and not warnings:
        print("✅ DEM passed all checks")
    
    if issues:
        print("\n❌ CRITICAL ISSUES:")
        for issue in issues:
            print(f"  - {issue}")
    
    if warnings:
        print("\n⚠️  WARNINGS:")
        for warning in warnings:
            print(f"  - {warning}")
    
    return len(issues) == 0
```

### Climate Data Validation

```python
def validate_climate_data(climate_files, dem_file):
    """
    Validate climate data against DEM
    """
    
    issues = []
    
    # Load DEM bounds
    with rasterio.open(dem_file) as dem_src:
        dem_bounds = dem_src.bounds
        dem_crs = dem_src.crs
    
    for var, file_path in climate_files.items():
        print(f"Checking {var}...")
        
        if file_path.endswith('.nc'):
            # NetCDF file
            ds = xr.open_dataset(file_path)
            
            # Check spatial coverage
            # (Implementation depends on projection)
            
        elif file_path.endswith('.tif'):
            # GeoTIFF file
            with rasterio.open(file_path) as src:
                # Check alignment with DEM
                if src.crs != dem_crs:
                    issues.append(f"{var}: CRS mismatch with DEM")
                
                # Check overlap
                if not rasterio.coords.disjoint_bounds(src.bounds, dem_bounds):
                    issues.append(f"{var}: No spatial overlap with DEM")
                
                # Check values
                data = src.read(1)
                
                if 'temp' in var or 'tmin' in var or 'tmax' in var:
                    if np.any(data < -100) or np.any(data > 60):
                        issues.append(f"{var}: Temperature values out of range")
                
                elif 'prcp' in var or 'precip' in var:
                    if np.any(data < 0) or np.any(data > 500):
                        issues.append(f"{var}: Precipitation values out of range")
    
    return issues
```

## Advanced Techniques

### Multi-Scale Analysis

```python
def prepare_multiscale_dems(base_dem, scales=[10, 30, 90]):
    """
    Create DEMs at multiple resolutions for scale-dependent analysis
    """
    
    output_dems = {}
    
    for scale in scales:
        output_file = f'dem_{scale}m.tif'
        
        # Resample using appropriate method
        if scale < 30:
            method = 'bilinear'  # Smooth for fine scales
        else:
            method = 'average'   # Aggregate for coarse scales
        
        gdal_command = f"""
            gdalwarp \
              -tr {scale} {scale} \
              -r {method} \
              {base_dem} \
              {output_file}
        """
        
        os.system(gdal_command)
        output_dems[scale] = output_file
    
    return output_dems
```

### Temporal Data Organization

```python
def organize_temporal_data(data_dir, output_structure='hierarchical'):
    """
    Organize climate data for efficient temporal processing
    """
    
    from datetime import datetime
    import shutil
    
    data_dir = Path(data_dir)
    
    if output_structure == 'hierarchical':
        # Organize as: year/month/day/variable.tif
        
        for file_path in data_dir.glob('*.tif'):
            # Parse filename (assumes: variable_YYYYMMDD.tif)
            parts = file_path.stem.split('_')
            
            if len(parts) >= 2:
                var_name = parts[0]
                date_str = parts[1]
                
                # Parse date
                date = datetime.strptime(date_str, '%Y%m%d')
                
                # Create directory structure
                year_dir = data_dir / str(date.year)
                month_dir = year_dir / f'{date.month:02d}'
                day_dir = month_dir / f'{date.day:02d}'
                
                day_dir.mkdir(parents=True, exist_ok=True)
                
                # Move file
                new_path = day_dir / f'{var_name}.tif'
                shutil.move(file_path, new_path)
    
    elif output_structure == 'netcdf':
        # Combine into NetCDF with time dimension
        
        import xarray as xr
        
        # Group by variable
        variables = {}
        
        for file_path in data_dir.glob('*.tif'):
            var_name = file_path.stem.split('_')[0]
            
            if var_name not in variables:
                variables[var_name] = []
            
            variables[var_name].append(file_path)
        
        # Create NetCDF for each variable
        for var_name, file_list in variables.items():
            # Sort by date
            file_list.sort()
            
            # Load all files
            arrays = []
            times = []
            
            for file_path in file_list:
                with rasterio.open(file_path) as src:
                    arrays.append(src.read(1))
                    
                    # Extract date from filename
                    date_str = file_path.stem.split('_')[1]
                    times.append(pd.to_datetime(date_str))
            
            # Create xarray dataset
            da = xr.DataArray(
                np.stack(arrays),
                dims=['time', 'y', 'x'],
                coords={'time': times}
            )
            
            # Save to NetCDF
            da.to_netcdf(data_dir / f'{var_name}_timeseries.nc')
```

### Parallel Processing Setup

```python
def prepare_for_parallel_processing(dem_file, tile_size=5000, overlap=100):
    """
    Tile DEM for parallel processing
    """
    
    output_dir = Path('tiles')
    output_dir.mkdir(exist_ok=True)
    
    with rasterio.open(dem_file) as src:
        # Calculate number of tiles
        n_tiles_x = int(np.ceil(src.width / tile_size))
        n_tiles_y = int(np.ceil(src.height / tile_size))
        
        tiles = []
        
        for i in range(n_tiles_y):
            for j in range(n_tiles_x):
                # Calculate window with overlap
                col_off = j * tile_size - overlap if j > 0 else 0
                row_off = i * tile_size - overlap if i > 0 else 0
                
                width = min(tile_size + overlap, src.width - col_off)
                height = min(tile_size + overlap, src.height - row_off)
                
                # Read tile
                window = rasterio.windows.Window(col_off, row_off, width, height)
                tile_data = src.read(1, window=window)
                
                # Get transform for tile
                tile_transform = rasterio.windows.transform(window, src.transform)
                
                # Save tile
                tile_file = output_dir / f'tile_{i:02d}_{j:02d}.tif'
                
                profile = src.profile.copy()
                profile.update({
                    'width': width,
                    'height': height,
                    'transform': tile_transform
                })
                
                with rasterio.open(tile_file, 'w', **profile) as dst:
                    dst.write(tile_data, 1)
                
                tiles.append({
                    'file': tile_file,
                    'row': i,
                    'col': j,
                    'window': window
                })
    
    # Save tile metadata
    import json
    with open(output_dir / 'tiles.json', 'w') as f:
        json.dump([{
            'file': str(t['file']),
            'row': t['row'],
            'col': t['col'],
            'window': {
                'col_off': t['window'].col_off,
                'row_off': t['window'].row_off,
                'width': t['window'].width,
                'height': t['window'].height
            }
        } for t in tiles], f, indent=2)
    
    return tiles
```

## Data Preparation Checklist

Before running EEMT calculations, ensure:

### ✅ DEM Preparation
- [ ] Downloaded appropriate resolution DEM
- [ ] Reprojected to suitable coordinate system
- [ ] Filled sinks and pits
- [ ] Clipped to study area
- [ ] Validated elevation ranges
- [ ] Created buffer zone if needed

### ✅ Climate Data
- [ ] Downloaded all required variables (tmin, tmax, prcp, vp)
- [ ] Matched spatial extent with DEM
- [ ] Aligned projection and resolution
- [ ] Validated data ranges
- [ ] Organized temporal structure

### ✅ Vegetation Data (if using EEMT_VEG)
- [ ] Acquired cloud-free imagery
- [ ] Calculated NDVI
- [ ] Estimated LAI
- [ ] Processed canopy height (if available)
- [ ] Matched resolution with DEM

### ✅ Quality Control
- [ ] No significant NoData gaps
- [ ] Consistent projections across datasets
- [ ] Reasonable value ranges
- [ ] Adequate spatial coverage
- [ ] Appropriate temporal coverage

## Summary

Proper data preparation is essential for accurate EEMT calculations. Key points:

1. **Start with quality DEM data** - Resolution and accuracy matter
2. **Ensure spatial alignment** - All data must match DEM extent and projection
3. **Validate thoroughly** - Check for issues before processing
4. **Consider scale** - Choose appropriate resolution for your analysis
5. **Document processing** - Keep track of all preparation steps

With properly prepared data, you're ready to run EEMT calculations following the [Quick Start Guide](quick-start.md) or advanced [Calculation Methods](index.md).

---

*For additional help with data preparation, see the [API Reference](../api-reference/index.md) or contact the development team.*