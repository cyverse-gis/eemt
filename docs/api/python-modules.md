---
title: Python Modules API
---

# Python Modules API Reference

## Overview

The EEMT Python package provides programmatic access to all calculation functions, data utilities, and workflow components. This reference documents the public API for custom workflow development and integration.

## Core Modules

### eemt.calculations

Core EEMT calculation functions.

```python
from eemt import calculations

# Traditional EEMT calculation
eemt_trad = calculations.calculate_eemt_traditional(
    temperature=temp_array,
    precipitation=precip_array,
    elevation=dem_array
)

# Topographic EEMT calculation
eemt_topo = calculations.calculate_eemt_topographic(
    temperature=temp_array,
    precipitation=precip_array,
    solar_radiation=solar_array,
    twi=twi_array,
    slope=slope_array
)
```

#### Functions

##### `calculate_eemt_traditional()`

Calculate EEMT using climate-based approach.

**Parameters:**
- `temperature` (ndarray): Monthly mean temperature [°C]
- `precipitation` (ndarray): Monthly precipitation [mm]
- `elevation` (ndarray, optional): Elevation for corrections [m]
- `lapse_rate` (float): Temperature lapse rate [°C/km], default -6.5

**Returns:**
- `dict`: Contains 'eemt', 'e_bio', 'e_ppt' arrays [MJ m⁻² yr⁻¹]

**Example:**
```python
import numpy as np
from eemt import calculations

# Monthly climate data
temp = np.array([5, 8, 12, 16, 20, 24, 26, 25, 22, 17, 11, 6])
precip = np.array([45, 52, 68, 84, 95, 78, 65, 72, 85, 73, 58, 48])

# Calculate EEMT
result = calculations.calculate_eemt_traditional(temp, precip)
print(f"Annual EEMT: {result['eemt']:.2f} MJ/m²/yr")
print(f"Biological Energy: {result['e_bio']:.2f} MJ/m²/yr")
print(f"Precipitation Energy: {result['e_ppt']:.2f} MJ/m²/yr")
```

##### `calculate_eemt_topographic()`

Calculate EEMT with topographic corrections.

**Parameters:**
- `temperature` (ndarray): Temperature data [°C]
- `precipitation` (ndarray): Precipitation data [mm]
- `solar_radiation` (ndarray): Annual solar radiation [MJ/m²]
- `twi` (ndarray): Topographic wetness index
- `slope` (ndarray): Slope angle [degrees]
- `aspect` (ndarray, optional): Aspect angle [degrees]

**Returns:**
- `dict`: Enhanced EEMT components with topographic effects

### eemt.solar

Solar radiation calculation utilities.

```python
from eemt import solar

# Calculate daily solar radiation
daily_solar = solar.calculate_daily_radiation(
    dem=elevation_data,
    day_of_year=180,
    latitude=32.5,
    step_minutes=15
)

# Annual solar radiation
annual_solar = solar.calculate_annual_radiation(
    dem=elevation_data,
    latitude=32.5,
    step_minutes=15,
    num_threads=8
)
```

#### Functions

##### `calculate_daily_radiation()`

Calculate solar radiation for a single day.

**Parameters:**
- `dem` (ndarray): Digital elevation model [m]
- `day_of_year` (int): Julian day (1-365)
- `latitude` (float): Site latitude [degrees]
- `step_minutes` (int): Time step for calculation [minutes]
- `linke_turbidity` (float): Atmospheric turbidity (1-8)
- `albedo` (float): Surface albedo (0-1)

**Returns:**
- `ndarray`: Daily solar radiation [MJ/m²/day]

##### `calculate_annual_radiation()`

Calculate solar radiation for entire year.

**Parameters:**
- `dem` (ndarray): Digital elevation model [m]
- `latitude` (float): Site latitude [degrees]
- `step_minutes` (int): Time step [minutes]
- `num_threads` (int): Parallel threads to use
- `output_dir` (str, optional): Directory for intermediate files

**Returns:**
- `dict`: Contains daily and monthly radiation arrays

### eemt.climate

Climate data retrieval and processing.

```python
from eemt import climate

# Download DAYMET data
climate_data = climate.download_daymet(
    bounds=(-111.0, 32.0, -110.5, 32.5),
    years=range(2020, 2023),
    variables=['tmin', 'tmax', 'prcp']
)

# Process climate data
processed = climate.process_climate_data(
    climate_data,
    target_crs='EPSG:32612'
)
```

#### Functions

##### `download_daymet()`

Download DAYMET climate data.

**Parameters:**
- `bounds` (tuple): Bounding box (west, south, east, north)
- `years` (list): Years to download
- `variables` (list): Climate variables to retrieve
- `output_dir` (str): Download directory

**Returns:**
- `xarray.Dataset`: Climate data

##### `process_climate_data()`

Process and reproject climate data.

**Parameters:**
- `climate_data` (xarray.Dataset): Raw climate data
- `target_crs` (str): Target coordinate system
- `target_resolution` (float): Target resolution [m]

**Returns:**
- `xarray.Dataset`: Processed climate data

### eemt.io

Input/output utilities for various data formats.

```python
from eemt import io

# Read GeoTIFF
dem = io.read_geotiff('elevation.tif')

# Write results
io.write_geotiff(
    data=eemt_result,
    filepath='eemt_output.tif',
    crs=dem.crs,
    transform=dem.transform
)

# Read NetCDF
climate = io.read_netcdf('daymet_2020.nc')
```

#### Functions

##### `read_geotiff()`

Read GeoTIFF file with metadata.

**Parameters:**
- `filepath` (str): Path to GeoTIFF file
- `band` (int): Band number to read (default 1)
- `as_dataset` (bool): Return xarray Dataset

**Returns:**
- `GeoTIFFData`: Object with data, CRS, and transform

##### `write_geotiff()`

Write data to GeoTIFF format.

**Parameters:**
- `data` (ndarray): Data array to write
- `filepath` (str): Output file path
- `crs` (CRS): Coordinate reference system
- `transform` (Affine): Affine transformation
- `compress` (str): Compression method ('lzw', 'deflate')

### eemt.utils

Utility functions for data processing.

```python
from eemt import utils

# Calculate topographic metrics
slope, aspect = utils.calculate_slope_aspect(dem)
twi = utils.calculate_twi(dem, flow_accumulation)

# Reproject data
reprojected = utils.reproject_raster(
    source_data,
    source_crs='EPSG:4326',
    target_crs='EPSG:32612'
)
```

#### Functions

##### `calculate_slope_aspect()`

Calculate slope and aspect from DEM.

**Parameters:**
- `dem` (ndarray): Digital elevation model
- `resolution` (float): Pixel resolution [m]
- `algorithm` (str): 'horn' or 'zevenbergen'

**Returns:**
- `tuple`: (slope, aspect) arrays

##### `calculate_twi()`

Calculate topographic wetness index.

**Parameters:**
- `dem` (ndarray): Digital elevation model
- `resolution` (float): Pixel resolution [m]

**Returns:**
- `ndarray`: TWI values

## Workflow Classes

### EEMTWorkflow

High-level workflow orchestration.

```python
from eemt import EEMTWorkflow

# Initialize workflow
workflow = EEMTWorkflow(
    dem_file='input_dem.tif',
    output_dir='./results',
    config={
        'start_year': 2020,
        'end_year': 2022,
        'step_minutes': 15,
        'num_threads': 8
    }
)

# Run complete workflow
workflow.run()

# Or run individual steps
workflow.prepare_inputs()
workflow.calculate_solar()
workflow.download_climate()
workflow.calculate_eemt()
workflow.generate_outputs()
```

#### Methods

##### `__init__()`

Initialize EEMT workflow.

**Parameters:**
- `dem_file` (str): Path to input DEM
- `output_dir` (str): Output directory
- `config` (dict): Workflow configuration

##### `run()`

Execute complete workflow.

**Parameters:**
- `skip_existing` (bool): Skip completed steps
- `cleanup` (bool): Remove intermediate files

**Returns:**
- `dict`: Workflow results and metadata

##### `calculate_solar()`

Run solar radiation calculations.

**Parameters:**
- `days` (list, optional): Specific days to calculate

**Returns:**
- `dict`: Solar radiation results

### SolarWorkflow

Solar radiation workflow management.

```python
from eemt import SolarWorkflow

# Configure solar workflow
solar_workflow = SolarWorkflow(
    dem_file='dem.tif',
    output_dir='./solar_output'
)

# Set parameters
solar_workflow.set_parameters(
    step_minutes=15,
    linke_turbidity=2.5,
    albedo=0.2
)

# Run calculations
results = solar_workflow.run(num_threads=8)
```

## Data Classes

### GeoTIFFData

Container for GeoTIFF data and metadata.

```python
from eemt.io import GeoTIFFData

# Create from arrays
geotiff = GeoTIFFData(
    data=data_array,
    crs='EPSG:32612',
    transform=affine_transform,
    bounds=(-111.0, 32.0, -110.5, 32.5)
)

# Access properties
print(f"Shape: {geotiff.shape}")
print(f"Resolution: {geotiff.resolution}")
print(f"CRS: {geotiff.crs}")

# Export to file
geotiff.to_file('output.tif', compress='lzw')
```

### ClimateData

Climate data container with utilities.

```python
from eemt.climate import ClimateData

# Load climate data
climate = ClimateData.from_daymet(
    bounds=bbox,
    years=[2020, 2021, 2022]
)

# Access variables
temperature = climate.temperature
precipitation = climate.precipitation

# Calculate derived metrics
pet = climate.calculate_pet()
vpd = climate.calculate_vpd()

# Resample to match DEM
climate_resampled = climate.resample_to(dem_grid)
```

## Exceptions

### EEMTError

Base exception for EEMT errors.

```python
from eemt.exceptions import (
    EEMTError,
    InvalidParameterError,
    DataNotFoundError,
    WorkflowError
)

try:
    workflow.run()
except InvalidParameterError as e:
    print(f"Invalid parameter: {e.parameter} = {e.value}")
except DataNotFoundError as e:
    print(f"Missing data: {e.data_type}")
except WorkflowError as e:
    print(f"Workflow failed at step: {e.step}")
```

## Configuration

### Default Configuration

```python
from eemt import config

# Access default configuration
defaults = config.get_defaults()
print(defaults['solar']['step_minutes'])  # 15
print(defaults['solar']['linke_turbidity'])  # 2.0

# Override defaults
config.set_default('solar.step_minutes', 10)

# Load from file
config.load_config('eemt_config.yaml')
```

### Configuration Schema

```yaml
# eemt_config.yaml
solar:
  step_minutes: 15
  linke_turbidity: 2.0
  albedo: 0.2
  
climate:
  source: "daymet"
  variables:
    - tmin
    - tmax
    - prcp
    
eemt:
  methods:
    - traditional
    - topographic
  
performance:
  num_threads: 8
  chunk_size: 1000
  use_gpu: false
```

## Logging

```python
import logging
from eemt import setup_logging

# Configure logging
setup_logging(
    level=logging.INFO,
    log_file='eemt.log',
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Use logger in modules
logger = logging.getLogger('eemt.solar')
logger.info('Starting solar calculations')
```

## Examples

### Complete Analysis Pipeline

```python
import numpy as np
from eemt import (
    EEMTWorkflow, 
    io, 
    utils,
    visualize
)

# Load input data
dem = io.read_geotiff('study_area_dem.tif')

# Calculate topographic metrics
slope, aspect = utils.calculate_slope_aspect(dem.data)
twi = utils.calculate_twi(dem.data)

# Initialize workflow
workflow = EEMTWorkflow(
    dem_file='study_area_dem.tif',
    output_dir='./analysis_results',
    config={
        'start_year': 2015,
        'end_year': 2020,
        'step_minutes': 15,
        'num_threads': 16
    }
)

# Run workflow with progress callback
def progress_callback(step, percent):
    print(f"{step}: {percent}% complete")

results = workflow.run(progress_callback=progress_callback)

# Visualize results
fig = visualize.plot_eemt_maps(
    results['eemt_traditional'],
    results['eemt_topographic'],
    title='EEMT Comparison'
)
fig.savefig('eemt_comparison.png', dpi=300)

# Generate statistics
stats = utils.calculate_statistics(
    results['eemt_topographic'],
    zones=vegetation_map
)
print(stats.to_dataframe())
```

### Custom Workflow

```python
from eemt import calculations, climate, solar
import concurrent.futures

def custom_eemt_analysis(dem_file, climate_bounds, years):
    """Custom EEMT workflow with parallel processing."""
    
    # Load DEM
    dem = io.read_geotiff(dem_file)
    
    # Parallel solar calculation
    with concurrent.futures.ProcessPoolExecutor() as executor:
        # Submit solar calculations for each year
        solar_futures = {
            year: executor.submit(
                solar.calculate_annual_radiation,
                dem.data,
                latitude=climate_bounds[1],
                step_minutes=15
            )
            for year in years
        }
        
        # Collect results
        solar_results = {
            year: future.result()
            for year, future in solar_futures.items()
        }
    
    # Download climate data
    climate_data = climate.download_daymet(
        bounds=climate_bounds,
        years=years,
        variables=['tmin', 'tmax', 'prcp', 'vp']
    )
    
    # Calculate EEMT for each year
    eemt_results = {}
    for year in years:
        eemt_results[year] = calculations.calculate_eemt_topographic(
            temperature=climate_data['tmax'].sel(time=str(year)),
            precipitation=climate_data['prcp'].sel(time=str(year)),
            solar_radiation=solar_results[year]['annual'],
            twi=utils.calculate_twi(dem.data)
        )
    
    return eemt_results
```

## Performance Optimization

### GPU Acceleration

```python
from eemt import gpu

# Check GPU availability
if gpu.is_available():
    print(f"GPU: {gpu.get_device_name()}")
    
    # Enable GPU acceleration
    workflow = EEMTWorkflow(
        dem_file='dem.tif',
        config={'use_gpu': True}
    )
```

### Dask Integration

```python
import dask.array as da
from eemt import calculations

# Create Dask arrays
dem_chunked = da.from_array(dem_data, chunks=(1000, 1000))
temp_chunked = da.from_array(temp_data, chunks=(100, 1000, 1000))

# Parallel computation
eemt_lazy = calculations.calculate_eemt_traditional(
    temperature=temp_chunked,
    precipitation=precip_chunked,
    elevation=dem_chunked
)

# Compute with progress bar
from dask.diagnostics import ProgressBar
with ProgressBar():
    eemt_result = eemt_lazy.compute()
```

---

*For more examples, see the [Examples Documentation](../examples/index.md). For installation, see the [Installation Guide](../installation/index.md).*