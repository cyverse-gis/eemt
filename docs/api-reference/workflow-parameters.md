# Workflow Parameters Reference

## Overview

This comprehensive reference documents all parameters available for EEMT and Solar Radiation workflows, including their scientific basis, valid ranges, and impact on calculations.

## Solar Radiation Workflow Parameters

### Core Parameters

#### `step` - Time Step
**Type**: Float  
**Default**: 15.0  
**Range**: 3.0 - 60.0 minutes  
**Required**: No

**Description**: Time interval for solar radiation calculations throughout the day. Smaller values provide higher temporal resolution but increase computation time.

**Scientific Basis**: The time step determines how frequently the sun's position is calculated and solar radiation is computed. This affects the accuracy of daily radiation totals, especially in complex terrain.

**Impact on Results**:
- **3-5 minutes**: High precision, captures rapid shadow changes in complex terrain
- **10-15 minutes**: Good balance of accuracy and performance for most applications
- **30-60 minutes**: Faster computation, suitable for regional assessments

**Example Usage**:
```python
# High-resolution analysis for complex terrain
parameters = {
    'step': 3.0,  # 3-minute intervals
    'num_threads': 8
}

# Regional assessment with moderate resolution
parameters = {
    'step': 15.0,  # 15-minute intervals (default)
    'num_threads': 4
}
```

#### `linke_value` - Atmospheric Turbidity
**Type**: Float  
**Default**: 3.0  
**Range**: 1.0 - 8.0  
**Required**: No

**Description**: Linke turbidity factor representing atmospheric optical thickness due to absorption and scattering.

**Scientific Basis**: The Linke turbidity factor accounts for the attenuation of solar radiation as it passes through the atmosphere. It combines the effects of:
- Water vapor absorption
- Aerosol scattering
- Molecular (Rayleigh) scattering

**Typical Values by Environment**:

| Environment | Linke Value | Description |
|------------|-------------|-------------|
| Clean mountain air | 1.0 - 2.0 | Very clear atmosphere, high elevation |
| Rural areas | 2.5 - 3.5 | Clean continental atmosphere |
| Urban areas | 3.5 - 5.0 | Moderate pollution and aerosols |
| Industrial zones | 5.0 - 8.0 | Heavy pollution, high aerosol content |

**Seasonal Variations**:
```python
# Winter (clearer atmosphere)
winter_params = {'linke_value': 2.5}

# Summer (more water vapor and aerosols)
summer_params = {'linke_value': 3.5}

# Monsoon/humid season
humid_params = {'linke_value': 4.5}
```

#### `albedo_value` - Surface Reflectance
**Type**: Float  
**Default**: 0.2  
**Range**: 0.0 - 1.0  
**Required**: No

**Description**: Fraction of incident solar radiation reflected by the surface.

**Scientific Basis**: Albedo affects the amount of diffuse radiation through multiple reflections between the surface and atmosphere. Higher albedo increases the total radiation received through these interactions.

**Typical Values by Surface Type**:

| Surface Type | Albedo | Example |
|-------------|--------|---------|
| Fresh snow | 0.80 - 0.95 | Alpine environments |
| Old snow | 0.50 - 0.70 | Late season snowpack |
| Desert sand | 0.30 - 0.45 | Arid regions |
| Grassland | 0.15 - 0.25 | Natural vegetation |
| Forest | 0.10 - 0.20 | Dense canopy |
| Water | 0.05 - 0.10 | Lakes, oceans |
| Asphalt | 0.05 - 0.15 | Urban surfaces |

**Land Cover Specific Examples**:
```python
# Forest analysis
forest_params = {
    'albedo_value': 0.15,
    'linke_value': 2.8  # Some canopy filtering
}

# Snow-covered terrain
snow_params = {
    'albedo_value': 0.85,
    'linke_value': 2.0  # Clear winter air
}

# Urban environment
urban_params = {
    'albedo_value': 0.12,
    'linke_value': 4.5  # Urban pollution
}
```

### Computational Parameters

#### `num_threads` - CPU Threads
**Type**: Integer  
**Default**: 4  
**Range**: 1 - 32  
**Required**: No

**Description**: Number of parallel processing threads for workflow execution.

**Performance Impact**:
```python
# Estimated processing times (10km x 10km @ 10m resolution)
# 1 thread:  ~4 hours
# 4 threads: ~1 hour (default)
# 8 threads: ~35 minutes
# 16 threads: ~20 minutes (diminishing returns)
```

**Resource Considerations**:
- Each thread requires ~2GB RAM
- I/O becomes bottleneck beyond 8-16 threads
- Leave 1-2 cores for system processes

### Advanced Parameters

#### `day` - Specific Day
**Type**: Integer  
**Range**: 1 - 365  
**Required**: No (processes all days if not specified)

**Description**: Calculate solar radiation for a specific day of year.

```python
# Summer solstice analysis
params = {'day': 172}  # June 21 (day 172)

# Winter solstice analysis  
params = {'day': 355}  # December 21 (day 355)
```

#### `beam_rad` - Beam Radiation Output
**Type**: Boolean  
**Default**: True  
**Required**: No

**Description**: Output direct beam radiation component separately.

#### `diff_rad` - Diffuse Radiation Output
**Type**: Boolean  
**Default**: True  
**Required**: No

**Description**: Output diffuse radiation component separately.

#### `refl_rad` - Reflected Radiation Output
**Type**: Boolean  
**Default**: False  
**Required**: No

**Description**: Output ground-reflected radiation component.

## EEMT Workflow Parameters

### Temporal Parameters

#### `start_year` - Start Year
**Type**: Integer  
**Default**: 2020  
**Range**: 1980 - 2024  
**Required**: Yes for EEMT workflow

**Description**: First year of climate data to process.

**Data Availability**:
- DAYMET v4: 1980 - present (1-2 year lag)
- Quality varies by year and region
- Recent years may have provisional data

#### `end_year` - End Year
**Type**: Integer  
**Default**: 2020  
**Range**: 1980 - 2024  
**Required**: Yes for EEMT workflow

**Description**: Last year of climate data to process.

**Multi-Year Processing**:
```python
# Single year analysis
params = {
    'start_year': 2020,
    'end_year': 2020
}

# 5-year climatology
params = {
    'start_year': 2016,
    'end_year': 2020
}

# Long-term analysis (30+ years)
params = {
    'start_year': 1990,
    'end_year': 2020,
    'num_threads': 16  # Use more threads for large datasets
}
```

### Climate Data Parameters

#### `daymet_variables` - Climate Variables
**Type**: List[str]  
**Default**: ['tmin', 'tmax', 'prcp', 'vp']  
**Options**: tmin, tmax, prcp, vp, srad, swe, dayl  
**Required**: No

**Description**: DAYMET climate variables to download and process.

**Variable Descriptions**:

| Variable | Description | Units | Use in EEMT |
|----------|-------------|-------|-------------|
| tmin | Daily minimum temperature | °C | Energy calculations |
| tmax | Daily maximum temperature | °C | Energy calculations |
| prcp | Daily precipitation | mm/day | Water flux |
| vp | Daily average vapor pressure | Pa | Humidity effects |
| srad | Incoming shortwave radiation | W/m² | Validation |
| swe | Snow water equivalent | kg/m² | Snow dynamics |
| dayl | Day length | seconds | Photoperiod |

#### `climate_buffer` - Spatial Buffer
**Type**: Float  
**Default**: 0.1  
**Range**: 0.0 - 1.0 degrees  
**Required**: No

**Description**: Buffer around DEM extent for climate data download.

```python
# Tight boundary (minimize download)
params = {'climate_buffer': 0.01}

# Include surrounding area for edge effects
params = {'climate_buffer': 0.25}
```

### EEMT Calculation Parameters

#### `eemt_method` - Calculation Method
**Type**: String  
**Default**: 'topographic'  
**Options**: 'traditional', 'topographic', 'vegetation'  
**Required**: No

**Description**: EEMT calculation methodology.

**Method Comparison**:

| Method | Description | Inputs Required | Best For |
|--------|-------------|-----------------|----------|
| traditional | Climate-based only | Climate data | Regional comparison |
| topographic | Terrain-modified | DEM + climate | Complex terrain |
| vegetation | Full ecosystem | DEM + climate + LAI | Detailed analysis |

**Method Selection**:
```python
# Simple regional assessment
params = {'eemt_method': 'traditional'}

# Mountain watershed analysis
params = {'eemt_method': 'topographic'}

# Ecosystem carbon studies
params = {'eemt_method': 'vegetation'}
```

#### `npp_model` - NPP Calculation
**Type**: String  
**Default**: 'miami'  
**Options**: 'miami', 'thornthwaite', 'user_defined'  
**Required**: No

**Description**: Net Primary Production model for biological energy calculation.

**Model Equations**:

**Miami Model**:
```python
# Temperature-limited
NPP_t = 3000 * (1 - exp(1.315 - 0.119 * T))

# Precipitation-limited  
NPP_p = 3000 * (1 - exp(-0.000664 * P))

# Actual NPP (minimum)
NPP = min(NPP_t, NPP_p)
```

**Thornthwaite Model**:
```python
# Based on evapotranspiration
NPP = 3000 * (AET / PET)
```

### Topographic Parameters

#### `slope_threshold` - Maximum Slope
**Type**: Float  
**Default**: 45.0  
**Range**: 0.0 - 90.0 degrees  
**Required**: No

**Description**: Maximum slope angle for stable soil formation.

**Geomorphological Context**:
- < 15°: Minimal erosion, stable soils
- 15-30°: Moderate erosion potential
- 30-45°: High erosion, thin soils
- > 45°: Bedrock exposure likely

#### `twi_threshold` - Wetness Threshold
**Type**: Float  
**Default**: 10.0  
**Range**: 0.0 - 20.0  
**Required**: No

**Description**: Topographic Wetness Index threshold for water accumulation zones.

**TWI Interpretation**:
- < 5: Ridge tops, dry areas
- 5-10: Hillslopes, normal drainage
- 10-15: Convergent areas, seasonal wetness
- > 15: Valley bottoms, persistent wetness

### Output Control Parameters

#### `output_format` - File Format
**Type**: String  
**Default**: 'geotiff'  
**Options**: 'geotiff', 'netcdf', 'zarr'  
**Required**: No

**Format Characteristics**:

| Format | Pros | Cons | Best For |
|--------|------|------|----------|
| GeoTIFF | Wide compatibility | Single variable per file | GIS integration |
| NetCDF | Multi-dimensional | Requires special tools | Time series |
| Zarr | Cloud-optimized | New format | Big data |

#### `output_compression` - Compression
**Type**: String  
**Default**: 'lzw'  
**Options**: 'none', 'lzw', 'deflate', 'zstd'  
**Required**: No

**Compression Trade-offs**:
```python
# No compression (fastest write, largest files)
params = {'output_compression': 'none'}

# LZW (good balance, wide support)
params = {'output_compression': 'lzw'}

# Deflate (better compression, slower)
params = {'output_compression': 'deflate'}

# Zstd (best compression, newest)
params = {'output_compression': 'zstd'}
```

#### `output_resolution` - Output Resolution
**Type**: Float  
**Default**: Same as input DEM  
**Range**: 1.0 - 1000.0 meters  
**Required**: No

**Description**: Resample output to different resolution.

```python
# Maintain input resolution
params = {}  # Default behavior

# Aggregate to coarser resolution
params = {'output_resolution': 30.0}  # 30m output

# Regional product
params = {'output_resolution': 100.0}  # 100m output
```

## Parameter Validation

### Input Validation Rules

```python
def validate_parameters(params: dict, workflow_type: str) -> dict:
    """Validate and sanitize workflow parameters"""
    
    # Common validations
    if params.get('step'):
        assert 3.0 <= params['step'] <= 60.0
    
    if params.get('linke_value'):
        assert 1.0 <= params['linke_value'] <= 8.0
    
    if params.get('albedo_value'):
        assert 0.0 <= params['albedo_value'] <= 1.0
    
    if params.get('num_threads'):
        assert 1 <= params['num_threads'] <= 32
    
    # EEMT-specific validations
    if workflow_type == 'eemt':
        assert params.get('start_year'), "start_year required for EEMT"
        assert params.get('end_year'), "end_year required for EEMT"
        assert params['start_year'] <= params['end_year']
        assert 1980 <= params['start_year'] <= 2024
        assert 1980 <= params['end_year'] <= 2024
    
    return params
```

### Parameter Combinations

#### High-Accuracy Solar Analysis
```python
high_accuracy = {
    'step': 3.0,
    'linke_value': 3.0,
    'albedo_value': 0.2,
    'num_threads': 16,
    'beam_rad': True,
    'diff_rad': True,
    'refl_rad': True
}
```

#### Quick Regional Assessment
```python
quick_regional = {
    'step': 30.0,
    'linke_value': 3.0,
    'albedo_value': 0.2,
    'num_threads': 4,
    'output_resolution': 100.0,
    'output_compression': 'lzw'
}
```

#### Climate Change Analysis
```python
climate_analysis = {
    'start_year': 1990,
    'end_year': 2020,
    'step': 15.0,
    'eemt_method': 'topographic',
    'daymet_variables': ['tmin', 'tmax', 'prcp', 'vp', 'srad'],
    'output_format': 'netcdf'
}
```

#### Snow-Dominated Watershed
```python
snow_watershed = {
    'step': 10.0,
    'linke_value': 2.5,  # Clear mountain air
    'albedo_value': 0.65,  # Snow average
    'start_year': 2020,
    'end_year': 2020,
    'daymet_variables': ['tmin', 'tmax', 'prcp', 'swe'],
    'slope_threshold': 35.0  # Avalanche consideration
}
```

## Performance Optimization Guide

### Memory Requirements

```python
def estimate_memory(dem_size_mb: float, params: dict) -> float:
    """Estimate memory requirements in GB"""
    
    base_memory = 2.0  # OS and runtime
    
    # DEM memory (multiple copies for processing)
    dem_memory = dem_size_mb * 4 / 1024  
    
    # Thread memory (2GB per thread)
    thread_memory = params.get('num_threads', 4) * 2
    
    # Time series memory (for EEMT)
    if params.get('start_year'):
        years = params['end_year'] - params['start_year'] + 1
        timeseries_memory = dem_size_mb * years * 365 / 1024
    else:
        timeseries_memory = 0
    
    return base_memory + dem_memory + thread_memory + timeseries_memory
```

### Processing Time Estimates

```python
def estimate_runtime(dem_pixels: int, params: dict) -> float:
    """Estimate runtime in hours"""
    
    # Base rate: pixels per second per thread
    if params.get('step', 15) <= 5:
        rate = 1000  # High resolution
    elif params.get('step', 15) <= 15:
        rate = 5000  # Medium resolution
    else:
        rate = 10000  # Low resolution
    
    threads = params.get('num_threads', 4)
    
    # Solar workflow
    days = 365
    solar_time = (dem_pixels * days) / (rate * threads * 3600)
    
    # EEMT additions
    if params.get('start_year'):
        years = params['end_year'] - params['start_year'] + 1
        eemt_time = solar_time * years * 1.5  # Climate data overhead
    else:
        eemt_time = solar_time
    
    return eemt_time
```

## Troubleshooting Parameters

### Common Parameter Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Out of memory | Too many threads | Reduce `num_threads` |
| Slow processing | Fine time step | Increase `step` to 15-30 |
| Poor results in shadows | Coarse time step | Decrease `step` to 3-5 |
| Unrealistic radiation | Wrong turbidity | Adjust `linke_value` for conditions |
| Missing diffuse radiation | Wrong albedo | Set appropriate `albedo_value` |
| DAYMET download fails | Invalid year range | Check data availability |
| Large output files | No compression | Enable `output_compression` |

### Parameter Debugging

```python
# Enable verbose logging
debug_params = {
    'step': 15.0,
    'num_threads': 1,  # Single thread for debugging
    'verbose': True,
    'debug': True,
    'log_level': 'DEBUG'
}
```

## Related Documentation

- [Workflow Examples](../examples/index.md)
- [API Reference](./index.md)
- [Scientific Background](../background/index.md)
- [Web Interface Guide](../web-interface/index.md)