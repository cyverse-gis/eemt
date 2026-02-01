---
title: Data Sources
---

# Data Sources for EEMT Calculations

## Overview

EEMT calculations require high-quality elevation and climate data. This guide covers accessing publicly available datasets optimized for Critical Zone analysis.

## Quick Reference

| Data Type | Source | Resolution | Coverage | API Access |
|-----------|--------|------------|----------|------------|
| **Elevation** | USGS 3DEP | 1m, 10m, 30m | United States | ✅ |
| | OpenTopography | Variable | Global | ✅ |
| | FABDEM | 30m | Global | ❌ |
| **Climate** | DAYMET | 1km daily | North America | ✅ |
| | PRISM | 800m monthly | United States | ✅ |
| | GridMET | 4km daily | United States | ✅ |
| **Satellite** | Landsat | 30m | Global | ✅ |
| | MODIS | 250m-1km | Global | ✅ |

## Elevation Data

### USGS 3DEP (3D Elevation Program)

**Best for**: High-resolution analysis in the United States

#### Access Methods

**1. National Map Downloader**
```bash
# Direct download interface
https://apps.nationalmap.gov/downloader/

# Select area of interest, choose elevation products:
# - 1m DEM (lidar-derived, best quality)
# - 1/3 arc-second (~10m, good coverage) 
# - 1 arc-second (~30m, complete coverage)
```

**2. USGS API Access**
```python
import requests
import geopandas as gpd

def download_3dep(bbox, resolution='10m'):
    """
    Download USGS 3DEP elevation data
    
    Parameters:
    bbox: [west, south, east, north] in decimal degrees
    resolution: '1m', '10m', or '30m'
    """
    
    base_url = "https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/"
    
    if resolution == '1m':
        dataset = "USGS_LPC"
    elif resolution == '10m':  
        dataset = "USGS_NED_13"
    else:
        dataset = "USGS_NED_1"
    
    # Construct download URL
    url = f"{base_url}{dataset}?west={bbox[0]}&south={bbox[1]}&east={bbox[2]}&north={bbox[3]}&outputFormat=GTiff"
    
    return url

# Example usage
arizona_bbox = [-111.5, 32.0, -110.5, 32.5]  
dem_url = download_3dep(arizona_bbox, '10m')
```

**3. Cloud-Optimized Access**
```python
import rasterio
from rasterio.session import AWSSession

# Access 3DEP COGs on AWS Open Data
aws_session = AWSSession(profile_name='default')
with rasterio.Env(session=aws_session):
    with rasterio.open('s3://prd-tnm/StagedProducts/Elevation/1m/Projects/...') as src:
        dem_data = src.read(1)
```

### OpenTopography

**Best for**: Global coverage, lidar access, research applications

#### Web Interface
```bash
# OpenTopography Portal
https://portal.opentopography.org/

# Select dataset:
# - SRTM GL1 (30m global)
# - SRTM GL3 (90m global)  
# - ALOS World 3D (30m global)
# - Regional lidar datasets
```

#### API Access
```python
import requests

def download_opentopo(bbox, dem_type='SRTMGL1'):
    """
    Download DEM from OpenTopography API
    
    Parameters:
    bbox: [west, south, east, north] in decimal degrees
    dem_type: 'SRTMGL1', 'SRTMGL3', 'ALOS', 'COP30', 'COP90'
    """
    
    base_url = "https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/"
    
    params = {
        'demtype': dem_type,
        'west': bbox[0],
        'south': bbox[1], 
        'east': bbox[2],
        'north': bbox[3],
        'outputFormat': 'GTiff'
    }
    
    response = requests.get(f"{base_url}/API/globaldem", params=params)
    
    if response.status_code == 200:
        with open(f'{dem_type}_dem.tif', 'wb') as f:
            f.write(response.content)
        return f'{dem_type}_dem.tif'
    else:
        raise Exception(f"Download failed: {response.status_code}")

# Example usage
bbox = [-111.5, 32.0, -110.5, 32.5]
dem_file = download_opentopo(bbox, 'SRTMGL1')
```

#### Lidar Point Cloud Access
```python
import pdal
import json

# Download lidar point cloud data
pipeline = {
    "pipeline": [
        {
            "type": "readers.ept",
            "filename": "https://cloud.sdsc.edu/v1/AUTH_opentopography/PC/CA_FullState_2019/ept.json",
            "bounds": "([-111.5, -111.0], [32.0, 32.5])"
        },
        {
            "type": "writers.las",
            "filename": "output.las"
        }
    ]
}

pdal_pipeline = pdal.Pipeline(json.dumps(pipeline))
pdal_pipeline.execute()
```

### Global DEMs

#### FABDEM (Forest And Buildings removed DEM)
```python
# Access via Google Earth Engine
import ee

ee.Initialize()

# Load FABDEM
fabdem = ee.Image("projects/sat-io/open-datasets/FABDEM")

# Export specific region
task = ee.batch.Export.image.toDrive(
    image=fabdem.select('elevation'),
    description='FABDEM_export',
    folder='EarthEngine',
    scale=30,
    region=ee.Geometry.Rectangle([-111.5, 32.0, -110.5, 32.5]),
    crs='EPSG:4326'
)
task.start()
```

#### Copernicus DEM
```bash
# Download via Copernicus Data Space
# https://dataspace.copernicus.eu/

# Available resolutions:
# - COP-DEM 30m (global)
# - COP-DEM 90m (global)

# API access requires registration
```

## Climate Data

### DAYMET (Daily Surface Weather Data)

**Best for**: High-resolution daily meteorology across North America

#### Variables Available
- **tmin**: Daily minimum temperature (°C)
- **tmax**: Daily maximum temperature (°C)  
- **prcp**: Daily precipitation (mm/day)
- **srad**: Shortwave radiation (W/m²)
- **vp**: Water vapor pressure (Pa)
- **swe**: Snow water equivalent (kg/m²)
- **dayl**: Day length (s/day)

#### API Access
```python
import requests
import xarray as xr
from datetime import datetime

def download_daymet(lat, lon, start_year, end_year, variables=['tmin', 'tmax', 'prcp']):
    """
    Download DAYMET data for point location
    
    Parameters:
    lat, lon: coordinates in decimal degrees
    start_year, end_year: year range
    variables: list of variable names
    """
    
    base_url = "https://daymet.ornl.gov/single-pixel/api/data"
    
    params = {
        'lat': lat,
        'lon': lon,
        'vars': ','.join(variables),
        'start': start_year,
        'end': end_year,
        'format': 'json'
    }
    
    response = requests.get(base_url, params=params)
    data = response.json()
    
    return data

# Example usage
tucson_data = download_daymet(32.25, -110.97, 2015, 2020, 
                            ['tmin', 'tmax', 'prcp', 'vp'])
```

#### Spatial Data Access
```python
def download_daymet_spatial(bbox, year, variable='tmin'):
    """
    Download DAYMET spatial data via THREDDS
    
    Parameters:
    bbox: [west, south, east, north]
    year: data year
    variable: 'tmin', 'tmax', 'prcp', 'srad', 'vp', 'swe', 'dayl'
    """
    
    base_url = "https://thredds.daac.ornl.gov/thredds/dodsC/ornldaac/1328"
    nc_url = f"{base_url}/daymet_v4_daily_na_{variable}_{year}.nc"
    
    # Open with xarray
    ds = xr.open_dataset(nc_url)
    
    # Subset to bounding box
    subset = ds.sel(
        x=slice(bbox[0], bbox[2]),
        y=slice(bbox[1], bbox[3])
    )
    
    return subset

# Example usage
bbox = [-111.5, 32.0, -110.5, 32.5]
temp_data = download_daymet_spatial(bbox, 2020, 'tmin')
```

#### Bulk Download Script
```python
import os
from concurrent.futures import ThreadPoolExecutor
import subprocess

def download_daymet_bulk(bbox, years, variables, output_dir):
    """
    Bulk download DAYMET data using wget
    """
    
    os.makedirs(output_dir, exist_ok=True)
    
    def download_file(url, filename):
        cmd = f"wget -O {output_dir}/{filename} '{url}'"
        subprocess.run(cmd, shell=True)
    
    download_tasks = []
    
    for year in years:
        for var in variables:
            url = f"https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/1328/daymet_v4_daily_na_{var}_{year}.nc"
            filename = f"daymet_{var}_{year}.nc"
            download_tasks.append((url, filename))
    
    # Parallel downloads
    with ThreadPoolExecutor(max_workers=4) as executor:
        for url, filename in download_tasks:
            executor.submit(download_file, url, filename)

# Example usage  
years = range(2015, 2021)
variables = ['tmin', 'tmax', 'prcp', 'vp']
download_daymet_bulk(bbox, years, variables, 'daymet_data')
```

### PRISM (Parameter-elevation Regressions on Independent Slopes Model)

**Best for**: High-resolution monthly climate normals for the United States

#### Access Methods
```python
import requests
from bs4 import BeautifulSoup

def download_prism(bbox, year, variable='ppt', temporal='monthly'):
    """
    Download PRISM data
    
    Parameters:
    bbox: [west, south, east, north]
    year: data year or 'normals' for 30-year averages
    variable: 'ppt', 'tmin', 'tmax', 'tmean', 'tdmean', 'vpdmin', 'vpdmax'
    temporal: 'monthly', 'daily', 'annual'
    """
    
    if year == 'normals':
        base_url = "https://prism.oregonstate.edu/normals/"
    else:
        base_url = "https://prism.oregonstate.edu/recent_years/"
    
    # PRISM requires spatial subsetting after download
    # Full datasets available at: ftp://prism.oregonstate.edu/
    
    print(f"PRISM data download instructions:")
    print(f"1. Visit: {base_url}")
    print(f"2. Download {variable} data for {year}")
    print(f"3. Use gdal_translate to subset:")
    print(f"   gdal_translate -projwin {bbox[0]} {bbox[3]} {bbox[2]} {bbox[1]} input.bil output.tif")

# Example usage
download_prism([-111.5, 32.0, -110.5, 32.5], 2020, 'ppt')
```

### GridMET

**Best for**: Daily meteorological data with broader spatial coverage than DAYMET

```python
import xarray as xr

def download_gridmet(bbox, year, variable='pr'):
    """
    Download GridMET data
    
    Parameters:  
    bbox: [west, south, east, north]
    year: data year
    variable: 'pr', 'tmmn', 'tmmx', 'rmax', 'rmin', 'vs', 'th', 'pet', 'erc', 'bi', 'fm100', 'fm1000'
    """
    
    base_url = "http://thredds.northwestknowledge.net:8080/thredds/dodsC/MET"
    nc_url = f"{base_url}/{variable}/{variable}_{year}.nc"
    
    # Open dataset
    ds = xr.open_dataset(nc_url)
    
    # Subset to bounding box
    subset = ds.sel(
        lon=slice(bbox[0], bbox[2]),
        lat=slice(bbox[1], bbox[3])
    )
    
    return subset

# Example usage
bbox = [-111.5, 32.0, -110.5, 32.5]
precip_data = download_gridmet(bbox, 2020, 'pr')
```

## Satellite Data

### Landsat (Vegetation Indices)

**Best for**: Long-term vegetation monitoring, NDVI calculation

#### Google Earth Engine Access
```python
import ee

ee.Initialize()

def get_landsat_collection(bbox, start_date, end_date, cloud_cover=20):
    """
    Get Landsat collection with cloud masking
    """
    
    # Define area of interest
    aoi = ee.Geometry.Rectangle(bbox)
    
    # Get Landsat 8 collection
    collection = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2') \
        .filterBounds(aoi) \
        .filterDate(start_date, end_date) \
        .filter(ee.Filter.lt('CLOUD_COVER', cloud_cover))
    
    def mask_clouds(image):
        # Cloud mask using QA_PIXEL band
        qa = image.select('QA_PIXEL')
        cloud_mask = qa.bitwiseAnd(1 << 3).eq(0)  # Cloud bit
        return image.updateMask(cloud_mask)
    
    # Apply cloud masking
    masked_collection = collection.map(mask_clouds)
    
    return masked_collection

def calculate_ndvi(image):
    """Calculate NDVI from Landsat image"""
    ndvi = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI')
    return image.addBands(ndvi)

# Example usage
bbox = [-111.5, 32.0, -110.5, 32.5]
collection = get_landsat_collection(bbox, '2020-01-01', '2020-12-31')
ndvi_collection = collection.map(calculate_ndvi)

# Get median NDVI for year
median_ndvi = ndvi_collection.select('NDVI').median()
```

#### Direct Archive Access
```python
import pystac_client
import rioxarray

# Access Landsat via STAC
catalog = pystac_client.Client.open("https://landsatlook.usgs.gov/stac-server")

# Search for Landsat scenes
search = catalog.search(
    collections=["landsat-c2l2-sr"],
    bbox=[-111.5, 32.0, -110.5, 32.5],
    datetime="2020-06-01/2020-08-31",
    query={"eo:cloud_cover": {"lt": 20}}
)

# Download and process
items = list(search.get_items())
for item in items[:5]:  # First 5 scenes
    red_asset = item.assets['red']
    nir_asset = item.assets['nir08']
    
    # Load bands
    red = rioxarray.open_rasterio(red_asset.href, chunks=True)
    nir = rioxarray.open_rasterio(nir_asset.href, chunks=True)
    
    # Calculate NDVI
    ndvi = (nir - red) / (nir + red)
```

### MODIS Products

**Best for**: Global vegetation monitoring, LAI/FPAR products

```python
import requests
from pyhdf.SD import SD, SDC
import numpy as np

def download_modis_lai(bbox, year, product='MYD15A3H'):
    """
    Download MODIS LAI product
    
    Parameters:
    bbox: [west, south, east, north] 
    year: data year
    product: 'MOD15A3H' (Terra) or 'MYD15A3H' (Aqua)
    """
    
    # MODIS data requires registration at:
    # https://urs.earthdata.nasa.gov/
    
    base_url = "https://e4ftl01.cr.usgs.gov/MOLA/"
    
    # Example for automated access (requires authentication)
    print(f"MODIS {product} download:")
    print(f"1. Register at: https://urs.earthdata.nasa.gov/")
    print(f"2. Use wget with credentials:")
    print(f"   wget --user=USERNAME --password=PASSWORD {base_url}{product}")
    print(f"3. Process HDF files to extract LAI layer")

# Process MODIS HDF file
def extract_modis_lai(hdf_file):
    """Extract LAI from MODIS HDF file"""
    
    # Open HDF file
    hdf = SD(hdf_file, SDC.READ)
    
    # Get LAI dataset
    lai_dataset = hdf.select('Lai_500m')
    lai_data = lai_dataset.get()
    
    # Apply scale factor and fill values
    scale_factor = lai_dataset.attributes()['scale_factor']
    fill_value = lai_dataset.attributes()['_FillValue']
    
    lai_data = lai_data.astype(np.float32)
    lai_data[lai_data == fill_value] = np.nan
    lai_data = lai_data * scale_factor
    
    return lai_data
```

## Data Integration Workflows

### Automated Climate Data Download
```python
import os
import subprocess
from datetime import datetime, timedelta

class ClimateDataManager:
    """Automated climate data download and processing"""
    
    def __init__(self, study_area, output_dir):
        self.bbox = study_area  # [west, south, east, north]
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
    
    def download_daymet_timeseries(self, start_year, end_year, variables):
        """Download DAYMET time series for study area"""
        
        for year in range(start_year, end_year + 1):
            for var in variables:
                url = f"https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/1328/daymet_v4_daily_na_{var}_{year}.nc"
                output_file = f"{self.output_dir}/daymet_{var}_{year}.nc"
                
                if not os.path.exists(output_file):
                    print(f"Downloading {var} for {year}...")
                    subprocess.run([
                        'wget', '-O', output_file, url
                    ], check=True)
    
    def process_to_monthly(self, variables):
        """Convert daily DAYMET to monthly averages"""
        
        for var in variables:
            # Use CDO (Climate Data Operators) if available
            input_pattern = f"{self.output_dir}/daymet_{var}_*.nc"
            output_file = f"{self.output_dir}/daymet_{var}_monthly.nc"
            
            cmd = f"cdo -monmean -mergetime {input_pattern} {output_file}"
            print(f"Processing {var} to monthly: {cmd}")
            # subprocess.run(cmd, shell=True, check=True)

# Example usage
study_area = [-111.5, 32.0, -110.5, 32.5]  # Arizona region
climate_manager = ClimateDataManager(study_area, 'climate_data')

# Download 5 years of data
climate_manager.download_daymet_timeseries(2015, 2020, ['tmin', 'tmax', 'prcp', 'vp'])
climate_manager.process_to_monthly(['tmin', 'tmax', 'prcp', 'vp'])
```

### Data Quality Control
```python
import rasterio
import numpy as np
from rasterio.mask import mask
import geopandas as gpd

def validate_dataset(filepath, data_type='elevation'):
    """Validate downloaded dataset for quality issues"""
    
    with rasterio.open(filepath) as src:
        data = src.read(1)
        profile = src.profile
        
        results = {
            'file': filepath,
            'crs': profile['crs'],
            'shape': data.shape,
            'dtype': profile['dtype'],
            'nodata': profile.get('nodata'),
            'valid_pixels': np.sum(~np.isnan(data)),
            'coverage_pct': np.sum(~np.isnan(data)) / data.size * 100
        }
        
        if data_type == 'elevation':
            results.update({
                'elevation_min': np.nanmin(data),
                'elevation_max': np.nanmax(data),
                'elevation_mean': np.nanmean(data),
                'has_negative_elev': np.any(data < -500),  # Flag suspicious values
            })
        elif data_type == 'temperature':
            results.update({
                'temp_min': np.nanmin(data),
                'temp_max': np.nanmax(data), 
                'temp_mean': np.nanmean(data),
                'realistic_range': np.all((data >= -50) & (data <= 60))  # Celsius range
            })
        elif data_type == 'precipitation':
            results.update({
                'precip_min': np.nanmin(data),
                'precip_max': np.nanmax(data),
                'precip_mean': np.nanmean(data),
                'no_negative': np.all(data >= 0)  # Precipitation can't be negative
            })
        
        return results

# Validate all datasets
datasets = [
    ('dem.tif', 'elevation'),
    ('temperature.tif', 'temperature'), 
    ('precipitation.tif', 'precipitation')
]

for filepath, data_type in datasets:
    if os.path.exists(filepath):
        validation = validate_dataset(filepath, data_type)
        print(f"\n{filepath} validation:")
        for key, value in validation.items():
            print(f"  {key}: {value}")
```

## Best Practices

### Data Selection Guidelines

1. **Match spatial resolutions** - Use consistent pixel sizes across datasets
2. **Align temporal periods** - Ensure climate data covers the same time period  
3. **Check coordinate systems** - Reproject data to common CRS if needed
4. **Validate extents** - Confirm all datasets cover your study area completely

### Storage and Organization
```
project/
├── data/
│   ├── elevation/
│   │   ├── raw/           # Original downloads
│   │   ├── processed/     # Reprojected, clipped
│   │   └── metadata/      # Data provenance
│   ├── climate/
│   │   ├── daymet/        # Daily meteorology  
│   │   ├── prism/         # Monthly normals
│   │   └── processed/     # Analysis-ready
│   └── satellite/
│       ├── landsat/       # Vegetation indices
│       └── modis/         # LAI products
├── scripts/               # Download automation
└── docs/                  # Data documentation
```

### Performance Tips

- **Use parallel downloads** for large datasets
- **Compress intermediate files** (LZW compression) 
- **Tile large rasters** for memory-efficient processing
- **Cache frequently used data** locally
- **Document data provenance** for reproducibility

---

Next: [GRASS GIS Setup and Configuration](../grass-gis/index.md)