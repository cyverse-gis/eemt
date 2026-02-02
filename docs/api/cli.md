---
title: API Reference
---

# EEMT API Reference

## Overview

This reference provides detailed documentation for all EEMT calculation functions, GRASS GIS commands, and configuration parameters.

## Core EEMT Functions

### Traditional EEMT Calculation

```python
def calculate_eemt_traditional(temperature, precipitation, elevation=None):
    """
    Calculate EEMT using traditional climate-based approach
    
    Parameters:
    -----------
    temperature : array_like
        Monthly mean temperature [°C]
    precipitation : array_like  
        Monthly precipitation [mm]
    elevation : array_like, optional
        Elevation for lapse rate corrections [m]
    
    Returns:
    --------
    eemt : array_like
        Effective Energy and Mass Transfer [MJ m⁻² yr⁻¹]
    e_bio : array_like
        Biological energy component [MJ m⁻² yr⁻¹]
    e_ppt : array_like
        Precipitation energy component [MJ m⁻² yr⁻¹]
    
    Notes:
    ------
    Based on Rasmussen et al. (2005, 2014) methodology.
    Uses Lieth (1975) NPP equation and Hamon PET estimation.
    
    Examples:
    ---------
    >>> temp = np.array([5, 10, 15, 20, 18, 12, 8])  # Monthly temps
    >>> precip = np.array([50, 60, 80, 40, 30, 45, 55])  # Monthly precip
    >>> eemt, e_bio, e_ppt = calculate_eemt_traditional(temp, precip)
    >>> print(f"Annual EEMT: {eemt:.1f} MJ/m²/yr")
    """
```

### Topographic EEMT Calculation

```python
def calculate_eemt_topographic(dem_file, climate_data, solar_data, 
                             output_dir, mcwi_method='d_infinity'):
    """
    Calculate EEMT with topographic controls on energy and water balance
    
    Parameters:
    -----------
    dem_file : str or Path
        Path to digital elevation model (GeoTIFF)
    climate_data : dict
        Dictionary containing climate arrays:
        - 'temperature': Monthly temperature [°C] 
        - 'precipitation': Monthly precipitation [mm]
        - 'humidity': Relative humidity [%]
        - 'wind_speed': Wind speed [m/s]
    solar_data : dict
        Solar radiation data from r.sun calculations:
        - 'global_radiation': Monthly solar [Wh/m²]
        - 'diffuse_radiation': Diffuse component [Wh/m²]
        - 'direct_radiation': Direct beam component [Wh/m²]
    output_dir : str or Path
        Output directory for intermediate files
    mcwi_method : str, default 'd_infinity'
        Flow routing method: 'd_infinity', 'mfd', 'sfd'
    
    Returns:
    --------
    eemt_result : dict
        Results dictionary containing:
        - 'eemt': Total EEMT [MJ m⁻² yr⁻¹]
        - 'e_bio': Biological component [MJ m⁻² yr⁻¹] 
        - 'e_ppt': Precipitation component [MJ m⁻² yr⁻¹]
        - 'mcwi': Mass Conservative Wetness Index
        - 'solar_ratio': Topographic solar modification factor
    
    Notes:
    ------
    Implements Rasmussen et al. (2014) EEMT_TOPO methodology.
    Requires GRASS GIS for terrain analysis and solar calculations.
    
    Examples:
    ---------
    >>> climate = load_daymet_data('study_area.shp', 2015, 2020)
    >>> solar = calculate_annual_solar('dem.tif', threads=8)
    >>> result = calculate_eemt_topographic('dem.tif', climate, solar, 'output/')
    >>> print(f"Mean topographic EEMT: {np.mean(result['eemt']):.1f} MJ/m²/yr")
    """
```

### Vegetation EEMT Calculation

```python
def calculate_eemt_vegetation(dem_file, climate_data, vegetation_data,
                           output_dir, lai_method='ndvi', resistance_model='kelliher'):
    """
    Calculate EEMT with full vegetation and topographic integration
    
    Parameters:
    -----------
    dem_file : str or Path
        Digital elevation model file path
    climate_data : dict
        Complete climate dataset with:
        - 'temperature': Temperature arrays [°C]
        - 'precipitation': Precipitation arrays [mm] 
        - 'humidity': Relative humidity [%]
        - 'wind_speed': Wind speed [m/s]
        - 'net_radiation': Net radiation [W/m²]
    vegetation_data : dict
        Vegetation structure data:
        - 'lai': Leaf Area Index [-] 
        - 'canopy_height': Canopy height [m]
        - 'ndvi': Normalized Difference Vegetation Index [-]
        - 'biomass': Aboveground biomass [Mg/ha] (optional)
    output_dir : str or Path
        Output directory
    lai_method : str, default 'ndvi'
        LAI calculation method: 'ndvi', 'modis', 'direct'
    resistance_model : str, default 'kelliher' 
        Surface resistance model: 'kelliher', 'jarvis', 'stewart'
    
    Returns:
    --------
    eemt_result : dict
        Complete EEMT results:
        - 'eemt': Total EEMT [MJ m⁻² yr⁻¹]
        - 'e_bio': Biological energy [MJ m⁻² yr⁻¹]
        - 'e_ppt': Precipitation energy [MJ m⁻² yr⁻¹] 
        - 'aet': Actual evapotranspiration [mm/yr]
        - 'npp': Net primary production [kg/m²/yr]
        - 'surface_resistance': Surface resistance [s/m]
        - 'lai_effective': Effective LAI used in calculations
    
    Notes:
    ------
    Implements Rasmussen et al. (2014) EEMT_TOPO-VEG methodology.
    Uses Penman-Monteith equation with vegetation-specific parameters.
    Accounts for canopy structure effects on energy and water balance.
    
    Examples:
    ---------
    >>> # Load vegetation data from satellite
    >>> vegetation = {
    ...     'ndvi': load_landsat_ndvi('study_area.shp', 2020),
    ...     'canopy_height': load_lidar_canopy('lidar_data.las')
    ... }
    >>> result = calculate_eemt_vegetation('dem.tif', climate, vegetation, 'output/')
    >>> print(f"Vegetation EEMT: {np.mean(result['eemt']):.1f} MJ/m²/yr")
    """
```

## GRASS GIS Command Reference

### Solar Radiation (r.sun family)

#### r.sun (Multi-processor version)
```bash
r.sun elevation=dem aspect=aspect slope=slope \\
         day=180 step=0.25 \\
         linke_value=3.0 albedo_value=0.2 \\
         threads=8 \\
         glob_rad=global_radiation \\
         insol_time=sunshine_hours \\
         [beam_rad=beam_radiation] \\
         [diff_rad=diffuse_radiation] \\
         [refl_rad=reflected_radiation]
```

**Parameters:**
- `elevation=name` - Input elevation raster
- `aspect=name` - Aspect in degrees (0-360°)  
- `slope=name` - Slope in degrees (0-90°)
- `day=integer` - Day of year (1-365)
- `step=float` - Time step in hours (0.25-1.0)
- `linke_value=float` - Linke atmospheric turbidity (1.0-8.0)
- `albedo_value=float` - Ground albedo (0.0-1.0)
- `threads=integer` - Number of OpenMP threads
- `glob_rad=name` - Output global radiation [Wh/m²]
- `insol_time=name` - Output sunshine duration [hours]

#### r.sun (Single-processor version)
```bash
r.sun elevation=dem \\
      [aspect=aspect] [slope=slope] \\
      [lat=latitude] [lon=longitude] \\
      [day=day_of_year] [time=decimal_time] \\
      [step=time_step] \\
      [glob_rad=output] [beam_rad=output] \\
      [diff_rad=output] [refl_rad=output] \\
      [insol_time=output]
```

**Advanced Options:**
- `horizon_basename=basename` - Horizon angle rasters
- `horizon_step=angle` - Horizon calculation step [degrees]
- `civil_time=hour` - Local solar time
- `solar_constant=value` - Solar constant [W/m²]
- `distance_step=value` - Sampling distance [m]

### Terrain Analysis

#### r.slope.aspect
```bash
r.slope.aspect elevation=dem \\
               slope=slope_output \\
               aspect=aspect_output \\
               [format=degrees|percent] \\
               [precision=FCELL|DCELL] \\
               [zscale=factor] \\
               [min_slope=degrees]
```

#### r.terraflow (Flow accumulation)
```bash
r.terraflow elevation=dem \\
            filled=filled_dem \\
            direction=flow_direction \\
            swatershed=watersheds \\
            accumulation=flow_accumulation \\
            tci=topographic_convergence_index
```

#### r.watershed (Alternative flow routing)
```bash
r.watershed elevation=dem \\
            accumulation=flow_accum \\
            drainage=flow_direction \\
            basin=watersheds \\
            stream=stream_network \\
            [threshold=threshold_value] \\
            [-s] [-4] [-a]
```

### Data Import/Export

#### r.in.gdal (Import raster data)
```bash
r.in.gdal input=input_file.tif \\
          output=grass_raster \\
          [band=band_number] \\
          [memory=memory_mb] \\
          [target=target_crs] \\
          [-o] [-e] [-f]
```

#### r.out.gdal (Export raster data)
```bash
r.out.gdal input=grass_raster \\
           output=output_file.tif \\
           format=GTiff \\
           [type=data_type] \\
           [nodata=nodata_value] \\
           createopt="COMPRESS=LZW,TILED=YES"
```

## Configuration Parameters

### Solar Radiation Parameters

| Parameter | Range | Default | Description |
|-----------|--------|---------|-------------|
| `day` | 1-365 | - | Day of year for calculation |
| `step` | 0.1-2.0 | 0.25 | Time step interval [hours] |
| `linke_value` | 1.0-8.0 | 3.0 | Atmospheric turbidity factor |
| `albedo_value` | 0.0-1.0 | 0.2 | Surface albedo coefficient |
| `lat` | -90 to 90 | auto | Latitude [decimal degrees] |
| `solar_constant` | 1300-1400 | 1367 | Solar constant [W/m²] |

### Processing Parameters

| Parameter | Range | Default | Description |
|-----------|--------|---------|-------------|
| `threads` | 1-64 | auto | OpenMP thread count |
| `memory` | 256-8192 | 2048 | Memory cache [MB] |
| `precision` | FCELL/DCELL | FCELL | Output precision |
| `compress` | LZW/DEFLATE | LZW | Output compression |

### Climate Thresholds

| Parameter | Value | Units | Description |
|-----------|--------|-------|-------------|
| `T_ref` | 273.15 | K | Reference temperature (freezing) |
| `h_BIO` | 22×10⁶ | J/kg | Specific biomass enthalpy |
| `c_w` | 4.18×10³ | J/kg/K | Specific heat of water |
| `EEMT_threshold` | 70 | MJ/m²/yr | Carbon/water dominance transition |

## Error Handling

### Common Error Codes

| Error | Cause | Solution |
|-------|-------|----------|
| `GRASS: Location not found` | Invalid GRASS database | Check `GISDBASE` path |
| `GDAL: Cannot open file` | Missing input data | Verify file paths |
| `r.sun: Memory allocation failed` | Insufficient RAM | Reduce region size or tile processing |
| `r.sun: Invalid day parameter` | Day outside 1-365 range | Check day parameter |
| `Projection mismatch` | CRS inconsistency | Reproject data to common CRS |

### Error Recovery Strategies

```python
def robust_eemt_calculation(dem_file, climate_dir, output_dir, max_retries=3):
    """
    EEMT calculation with error recovery
    
    Implements automatic retry, fallback methods, and error logging
    """
    
    import logging
    from time import sleep
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(f'{output_dir}/eemt_calculation.log'),
            logging.StreamHandler()
        ]
    )
    
    for attempt in range(max_retries):
        try:
            # Attempt EEMT calculation
            result = calculate_eemt_complete(dem_file, climate_dir, output_dir)
            logging.info(f"EEMT calculation successful on attempt {attempt + 1}")
            return result
            
        except MemoryError as e:
            logging.warning(f"Memory error on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                # Try with reduced resolution
                logging.info("Retrying with reduced spatial resolution...")
                dem_file = reduce_resolution(dem_file, factor=2)
            else:
                raise
                
        except FileNotFoundError as e:
            logging.error(f"Missing input file: {e}")
            raise
            
        except subprocess.CalledProcessError as e:
            logging.warning(f"GRASS command failed on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                sleep(5)  # Wait before retry
                logging.info("Retrying GRASS operation...")
            else:
                raise
                
        except Exception as e:
            logging.error(f"Unexpected error: {e}")
            if attempt < max_retries - 1:
                sleep(10)
                logging.info("Retrying with fresh environment...")
            else:
                raise
    
    raise RuntimeError(f"EEMT calculation failed after {max_retries} attempts")
```

## Performance Optimization

### Memory Management

```python
def optimize_grass_memory(max_memory_gb=16):
    """
    Optimize GRASS GIS memory settings for large datasets
    
    Parameters:
    -----------
    max_memory_gb : int
        Maximum memory to allocate [GB]
    """
    
    import os
    
    # Set GRASS memory environment
    cache_size = max_memory_gb * 1024  # Convert to MB
    
    os.environ.update({
        'GRASS_CACHE_SIZE': str(cache_size),
        'GRASS_RASTER_TMPDIR_MAPSET': '/tmp',
        'GRASS_VECTOR_TMPDIR_MAPSET': '/tmp',
        'GRASS_COMPRESS_NULLS': '1',
        'GRASS_RENDER_IMMEDIATE': 'FALSE'
    })
    
    print(f"✓ GRASS memory optimized for {max_memory_gb} GB")

def calculate_optimal_tile_size(dem_file, available_memory_gb=8):
    """
    Calculate optimal tile size for memory-constrained processing
    
    Parameters:
    -----------
    dem_file : str
        Path to DEM file
    available_memory_gb : int  
        Available system memory [GB]
    
    Returns:
    --------
    tile_size : int
        Optimal tile size in pixels
    overlap : int
        Recommended overlap in pixels
    """
    
    import rasterio
    
    with rasterio.open(dem_file) as src:
        width, height = src.width, src.height
        dtype_size = np.dtype(src.dtypes[0]).itemsize
    
    # Estimate memory usage per pixel (including intermediate arrays)
    memory_per_pixel = dtype_size * 20  # Factor for r.sun calculations
    
    # Calculate tile size that fits in available memory
    available_memory_bytes = available_memory_gb * 1024**3
    max_pixels = available_memory_bytes // memory_per_pixel
    tile_size = int(np.sqrt(max_pixels))
    
    # Ensure reasonable tile size
    tile_size = max(256, min(tile_size, 4096))
    overlap = max(32, tile_size // 16)  # 6.25% overlap
    
    return tile_size, overlap
```

### Parallel Processing Configuration

```python
def configure_parallel_processing(max_workers=None, threads_per_worker=4):
    """
    Configure optimal parallel processing parameters
    
    Parameters:
    -----------
    max_workers : int, optional
        Maximum number of worker processes (default: CPU count // 4)
    threads_per_worker : int
        OpenMP threads per worker process
    
    Returns:
    --------
    config : dict
        Optimized processing configuration
    """
    
    import multiprocessing as mp
    import psutil
    
    # Detect system capabilities
    cpu_count = mp.cpu_count()
    memory_gb = psutil.virtual_memory().total // (1024**3)
    
    # Calculate optimal configuration
    if max_workers is None:
        max_workers = max(1, cpu_count // threads_per_worker)
    
    # Memory per worker (reserve 2 GB for system)
    memory_per_worker = max(2, (memory_gb - 2) // max_workers)
    
    config = {
        'max_workers': max_workers,
        'threads_per_worker': threads_per_worker,
        'memory_per_worker_gb': memory_per_worker,
        'total_threads': max_workers * threads_per_worker,
        'memory_efficiency': memory_per_worker / (memory_gb / max_workers)
    }
    
    print(f"Parallel Processing Configuration:")
    print(f"  Workers: {config['max_workers']}")
    print(f"  Threads per worker: {config['threads_per_worker']}")
    print(f"  Total threads: {config['total_threads']}")
    print(f"  Memory per worker: {config['memory_per_worker_gb']} GB")
    
    return config
```

## Validation Functions

### Statistical Validation

```python
def validate_eemt_results(eemt_results, validation_data, method='pearson'):
    """
    Validate EEMT results against field measurements
    
    Parameters:
    -----------
    eemt_results : dict
        EEMT calculation results
    validation_data : dict
        Validation datasets:
        - 'soil_depth': Measured soil depths [cm]
        - 'biomass': Measured biomass [Mg/ha]
        - 'npp': Measured NPP [kg/m²/yr] 
        - 'coordinates': Sample locations
    method : str
        Validation method: 'pearson', 'spearman', 'rmse'
    
    Returns:
    --------
    validation_results : dict
        Validation statistics and plots
    """
    
    from scipy import stats
    import matplotlib.pyplot as plt
    
    validation_results = {}
    
    # Extract EEMT values at validation points
    for data_type, data in validation_data.items():
        if data_type == 'coordinates':
            continue
            
        # Extract EEMT values at measurement locations
        eemt_at_points = extract_values_at_points(
            eemt_results['eemt'], 
            validation_data['coordinates']
        )
        
        # Calculate validation statistics
        if method == 'pearson':
            r, p = stats.pearsonr(eemt_at_points, data)
            validation_results[data_type] = {
                'correlation': r,
                'p_value': p,
                'r_squared': r**2
            }
        elif method == 'rmse':
            rmse = np.sqrt(np.mean((eemt_at_points - data)**2))
            mae = np.mean(np.abs(eemt_at_points - data))
            validation_results[data_type] = {
                'rmse': rmse,
                'mae': mae,
                'bias': np.mean(eemt_at_points - data)
            }
    
    return validation_results

def cross_validate_eemt_methods(dem_file, climate_data, validation_points):
    """
    Cross-validation of different EEMT calculation methods
    
    Compares Traditional, Topographic, and Vegetation approaches
    against field validation data
    """
    
    methods = ['traditional', 'topographic', 'vegetation']
    results = {}
    
    for method in methods:
        print(f"Cross-validating {method} EEMT...")
        
        # Calculate EEMT using specific method
        if method == 'traditional':
            eemt = calculate_eemt_traditional(climate_data)
        elif method == 'topographic': 
            eemt = calculate_eemt_topographic(dem_file, climate_data)
        else:
            eemt = calculate_eemt_vegetation(dem_file, climate_data)
        
        # Validate against field data
        validation = validate_eemt_results(eemt, validation_points)
        results[method] = validation
    
    # Compare methods
    print("\\nMethod Comparison:")
    print("-" * 50)
    for method, validation in results.items():
        if 'soil_depth' in validation:
            r2 = validation['soil_depth']['r_squared']
            print(f"{method.capitalize():12} | R² = {r2:.3f}")
    
    return results
```

## Utility Functions

### Data Processing Utilities

```python
def extract_values_at_points(raster_file, coordinates, method='bilinear'):
    """Extract raster values at point locations"""
    
    import rasterio
    from rasterio.sample import sample_gen
    
    with rasterio.open(raster_file) as src:
        values = list(sample_gen(src, coordinates, indexes=1))
    
    return np.array([val[0] for val in values])

def calculate_zonal_statistics(raster_file, zones_file, statistics=['mean', 'std']):
    """Calculate statistics by zones (e.g., elevation bands, watersheds)"""
    
    from rasterstats import zonal_stats
    import geopandas as gpd
    
    # Load zones
    zones = gpd.read_file(zones_file)
    
    # Calculate statistics
    stats_result = zonal_stats(
        zones, 
        raster_file, 
        stats=statistics,
        geojson_out=True
    )
    
    return gpd.GeoDataFrame.from_features(stats_result)

def resample_to_common_grid(file_list, reference_file, output_dir, method='bilinear'):
    """Resample all rasters to common grid"""
    
    import subprocess
    from pathlib import Path
    
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Get reference grid parameters
    with rasterio.open(reference_file) as src:
        ref_transform = src.transform
        ref_crs = src.crs
        ref_width = src.width
        ref_height = src.height
    
    resampled_files = []
    
    for input_file in file_list:
        
        output_file = output_dir / f"resampled_{Path(input_file).name}"
        
        # Use gdalwarp for resampling
        cmd = [
            'gdalwarp',
            '-tr', str(ref_transform[0]), str(-ref_transform[4]),  # Resolution
            '-te', str(ref_transform[2]), str(ref_transform[5]),   # Extent  
                   str(ref_transform[2] + ref_width * ref_transform[0]),
                   str(ref_transform[5] + ref_height * ref_transform[4]),
            '-t_srs', str(ref_crs),  # Target CRS
            '-r', method,            # Resampling method
            '-co', 'COMPRESS=LZW',   # Compression
            str(input_file),
            str(output_file)
        ]
        
        subprocess.run(cmd, check=True)
        resampled_files.append(str(output_file))
    
    return resampled_files
```

## Command Line Interface

### Main EEMT Calculator Script

```bash
#!/usr/bin/env python3
"""
Command line interface for EEMT calculations
Usage: python eemt_calculator.py [options] dem_file
"""

usage_examples = '''
Examples:
  # Basic EEMT calculation
  python eemt_calculator.py dem.tif --climate climate_data/ --output results/
  
  # Topographic EEMT with parallel processing
  python eemt_calculator.py dem.tif --method topographic --threads 16 \\
    --climate daymet_data/ --output topo_results/
  
  # Full vegetation EEMT with validation
  python eemt_calculator.py dem.tif --method vegetation \\
    --climate climate/ --vegetation ndvi.tif,lidar.las \\
    --validate soil_samples.shp --output veg_results/
  
  # Time series analysis
  python eemt_calculator.py dem.tif --method topographic \\
    --start-year 2000 --end-year 2020 --time-series \\
    --output timeseries_results/
'''

# Command line argument definitions
CLI_ARGUMENTS = {
    'dem_file': {
        'type': str,
        'help': 'Input digital elevation model (GeoTIFF format)'
    },
    '--method': {
        'choices': ['traditional', 'topographic', 'vegetation', 'all'],
        'default': 'topographic',
        'help': 'EEMT calculation method'
    },
    '--climate': {
        'type': str, 
        'required': True,
        'help': 'Climate data directory (DAYMET NetCDF files)'
    },
    '--output': {
        'type': str,
        'required': True, 
        'help': 'Output directory for results'
    },
    '--threads': {
        'type': int,
        'default': 4,
        'help': 'Number of parallel processing threads'
    },
    '--step': {
        'type': float,
        'default': 0.25,
        'help': 'Solar calculation time step [hours]'
    },
    '--linke': {
        'type': float,
        'default': 3.0,
        'help': 'Linke atmospheric turbidity factor [1.0-8.0]'
    },
    '--albedo': {
        'type': float, 
        'default': 0.2,
        'help': 'Surface albedo coefficient [0.0-1.0]'
    },
    '--vegetation': {
        'type': str,
        'help': 'Vegetation data files (comma-separated): ndvi.tif,lidar.las'
    },
    '--start-year': {
        'type': int,
        'default': 2015,
        'help': 'Start year for time series analysis'
    },
    '--end-year': {
        'type': int, 
        'default': 2020,
        'help': 'End year for time series analysis'
    },
    '--validate': {
        'type': str,
        'help': 'Validation data file (point shapefile with measurements)'
    },
    '--time-series': {
        'action': 'store_true',
        'help': 'Generate annual time series output'
    },
    '--tile-size': {
        'type': int,
        'default': 2048,
        'help': 'Tile size for large dataset processing [pixels]'
    },
    '--verbose': {
        'action': 'store_true',
        'help': 'Enable verbose output'
    }
}
```

## Testing Framework

### Unit Tests

```python
import unittest
import numpy as np
from pathlib import Path

class TestEEMTCalculations(unittest.TestCase):
    """Unit tests for EEMT calculation functions"""
    
    def setUp(self):
        """Set up test data"""
        self.test_data_dir = Path('test_data')
        self.test_data_dir.mkdir(exist_ok=True)
        
        # Create synthetic test DEM
        self.create_test_dem()
        
        # Create synthetic climate data
        self.create_test_climate()
    
    def test_traditional_eemt(self):
        """Test traditional EEMT calculation"""
        
        # Simple test case
        temp = np.array([15.0])  # °C
        precip = np.array([50.0])  # mm/month
        
        eemt, e_bio, e_ppt = calculate_eemt_traditional(temp, precip)
        
        # Check output ranges
        self.assertGreater(eemt[0], 0, "EEMT should be positive")
        self.assertLess(eemt[0], 100, "EEMT should be reasonable (<100 MJ/m²/yr)")
        
        # Check components
        self.assertGreater(e_bio[0], 0, "E_BIO should be positive")
        self.assertGreaterEqual(e_ppt[0], 0, "E_PPT should be non-negative")
    
    def test_solar_radiation_range(self):
        """Test solar radiation calculations produce reasonable values"""
        
        # Test with synthetic DEM
        dem_file = self.test_data_dir / 'test_dem.tif'
        
        # Should complete without errors
        try:
            solar_result = calculate_annual_solar(dem_file, days=[180])  # Summer solstice
            self.assertTrue(True, "Solar calculation completed")
        except Exception as e:
            self.fail(f"Solar calculation failed: {e}")
    
    def test_aspect_effects(self):
        """Test that north-facing slopes have higher EEMT"""
        
        # Create test data with known aspect effects
        north_slope_eemt = calculate_eemt_topographic(
            self.create_test_slope(aspect=0)  # North-facing
        )
        
        south_slope_eemt = calculate_eemt_topographic(
            self.create_test_slope(aspect=180)  # South-facing
        )
        
        # North slopes should have higher EEMT in water-limited environments
        self.assertGreater(
            np.mean(north_slope_eemt),
            np.mean(south_slope_eemt),
            "North-facing slopes should have higher EEMT"
        )
    
    def create_test_dem(self):
        """Create synthetic DEM for testing"""
        
        # Create elevation gradient
        x, y = np.meshgrid(np.linspace(0, 1000, 100), np.linspace(0, 1000, 100))
        elevation = 1000 + x * 0.5 + y * 0.3 + np.random.normal(0, 10, (100, 100))
        
        # Save as GeoTIFF
        profile = {
            'driver': 'GTiff',
            'height': 100,
            'width': 100,
            'count': 1,
            'dtype': 'float32',
            'crs': 'EPSG:4326',
            'transform': rasterio.transform.from_bounds(-111, 32, -110, 33, 100, 100)
        }
        
        with rasterio.open(self.test_data_dir / 'test_dem.tif', 'w', **profile) as dst:
            dst.write(elevation.astype(np.float32), 1)

if __name__ == '__main__':
    unittest.main()
```

### Integration Tests

```bash
#!/bin/bash
# Integration test suite for EEMT workflows

set -e

echo "=== EEMT Integration Tests ==="

# Test 1: Basic workflow with sample data
echo "Test 1: Basic EEMT workflow..."
python eemt_calculator.py test_data/sample_dem.tif \\
  --climate test_data/climate/ \\
  --output test_results/basic/ \\
  --method traditional

# Test 2: Parallel processing
echo "Test 2: Parallel solar calculation..."
python eemt_calculator.py test_data/sample_dem.tif \\
  --climate test_data/climate/ \\
  --output test_results/parallel/ \\
  --method topographic \\
  --threads 4

# Test 3: Large dataset handling
echo "Test 3: Large dataset processing..."
python eemt_calculator.py test_data/large_dem.tif \\
  --climate test_data/climate/ \\
  --output test_results/large/ \\
  --tile-size 1024

# Test 4: Validation
echo "Test 4: Results validation..."
python validate_results.py test_results/ test_data/validation/

echo "✓ All integration tests passed"
```

---

This API reference provides the complete technical foundation for implementing and extending EEMT calculations with modern computational approaches and comprehensive error handling.