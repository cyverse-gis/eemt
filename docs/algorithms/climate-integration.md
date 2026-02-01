---
title: Climate Data Integration
description: Methods for acquiring, processing, and integrating climate data in EEMT calculations
---

# Climate Data Integration

## Overview

Climate data provides essential inputs for EEMT calculations, including temperature for energy flux calculations and precipitation for mass transfer. The framework primarily uses DAYMET v4 data, with support for other climate datasets through standardized processing pipelines.

## DAYMET Data Source

### Dataset Characteristics

DAYMET (Daily Surface Weather and Climatological Summaries) provides daily meteorological data for North America:

| Parameter | Description | Units | Range |
|-----------|-------------|-------|-------|
| **tmin** | Daily minimum temperature | °C | -60 to 50 |
| **tmax** | Daily maximum temperature | °C | -50 to 60 |
| **prcp** | Daily precipitation | mm/day | 0 to 500 |
| **vp** | Daily average vapor pressure | Pa | 0 to 10000 |
| **srad** | Shortwave radiation | W/m² | 0 to 800 |
| **swe** | Snow water equivalent | kg/m² | 0 to 2000 |

**Spatial Coverage**: North America (Canada, USA, Mexico, Hawaii, Puerto Rico)  
**Spatial Resolution**: 1 km × 1 km  
**Temporal Coverage**: 1980 - present (updated annually)  
**Projection**: Lambert Conformal Conic (LCC)

### DAYMET Projection Details

```python
# DAYMET v4 projection parameters
projection_params = {
    'proj': 'lcc',  # Lambert Conformal Conic
    'lat_1': 25,    # First standard parallel
    'lat_2': 60,    # Second standard parallel
    'lat_0': 42.5,  # Latitude of projection origin
    'lon_0': -100,  # Central meridian
    'x_0': 0,       # False easting
    'y_0': 0,       # False northing
    'ellps': 'WGS84',
    'units': 'm'
}

# PROJ4 string
proj4_string = "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
```

## Data Acquisition

### ORNL DAAC API Access

The EEMT framework retrieves DAYMET data through the ORNL DAAC API:

```python
def download_daymet_tile(tile_id, year, variable, output_dir):
    """
    Download DAYMET data for a specific tile
    
    Parameters:
    - tile_id: DAYMET tile identifier (e.g., "11754_1945")
    - year: Year of data (1980-present)
    - variable: Climate variable (tmin, tmax, prcp, vp, srad, swe)
    - output_dir: Output directory for downloaded files
    """
    
    base_url = "https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/1840/tiles"
    
    # Construct URL
    filename = f"{year}/{tile_id}_{year}_{variable}.nc"
    url = f"{base_url}/{filename}"
    
    # Download with retry logic
    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = requests.get(url, timeout=30)
            if response.status_code == 200:
                output_path = Path(output_dir) / f"{tile_id}_{year}_{variable}.nc"
                output_path.write_bytes(response.content)
                return output_path
        except Exception as e:
            if attempt == max_retries - 1:
                raise Exception(f"Failed to download {variable} for tile {tile_id}: {e}")
            time.sleep(2 ** attempt)  # Exponential backoff
```

### Spatial Subsetting

For study areas spanning multiple tiles or requiring subset regions:

```python
def get_daymet_subset(bbox, year, variables, output_dir):
    """
    Download DAYMET subset for bounding box
    
    Parameters:
    - bbox: [west, south, east, north] in decimal degrees
    - year: Year or range of years
    - variables: List of climate variables
    - output_dir: Output directory
    """
    
    # ORNL DAAC subset API
    api_url = "https://daymet.ornl.gov/single-pixel/api/data"
    
    params = {
        'lat': (bbox[1] + bbox[3]) / 2,  # Center latitude
        'lon': (bbox[0] + bbox[2]) / 2,  # Center longitude
        'vars': ','.join(variables),
        'years': f"{year}",
        'format': 'netcdf'
    }
    
    # For larger areas, use the subset tool
    if area_too_large_for_point(bbox):
        return use_daymet_subset_tool(bbox, year, variables)
    
    response = requests.get(api_url, params=params)
    return process_daymet_response(response, output_dir)
```

## Temperature Processing

### Mean Temperature Calculation

DAYMET provides minimum and maximum daily temperatures. Mean temperature is calculated as:

$$T_{mean} = \frac{T_{min} + T_{max}}{2}$$

For more accurate diurnal patterns:

```python
def calculate_hourly_temperature(tmin, tmax, hour):
    """
    Estimate hourly temperature using sine curve approximation
    
    Based on Parton & Logan (1981) method
    """
    
    # Time of temperature extremes
    hour_tmin = 6   # Typical sunrise
    hour_tmax = 15  # Mid-afternoon
    
    if hour_tmin <= hour <= hour_tmax:
        # Daytime warming
        t_range = tmax - tmin
        hours_elapsed = hour - hour_tmin
        hours_total = hour_tmax - hour_tmin
        temp = tmin + t_range * sin(pi * hours_elapsed / (2 * hours_total))
    else:
        # Nighttime cooling
        if hour > hour_tmax:
            hours_elapsed = hour - hour_tmax
            hours_total = 24 - hour_tmax + hour_tmin
        else:
            hours_elapsed = 24 - hour_tmax + hour
            hours_total = 24 - hour_tmax + hour_tmin
        
        t_sunset = tmin + 0.39 * (tmax - tmin)  # Temperature at sunset
        temp = t_sunset - (t_sunset - tmin) * sin(pi * hours_elapsed / (2 * hours_total))
    
    return temp
```

### Lapse Rate Adjustment

Temperature varies with elevation following environmental lapse rates:

$$T_z = T_{ref} + \Gamma \cdot (z - z_{ref})$$

Where:
- **T<sub>z</sub>** = Temperature at elevation z
- **T<sub>ref</sub>** = Reference temperature (from DAYMET)
- **Γ** = Environmental lapse rate (typically -6.5°C/km)
- **z** = Target elevation
- **z<sub>ref</sub>** = DAYMET grid elevation

```python
def adjust_temperature_for_elevation(temp_daymet, dem, daymet_elevation):
    """
    Adjust DAYMET temperature to DEM resolution
    """
    
    # Standard environmental lapse rate
    lapse_rate = -6.5  # °C per 1000m
    
    # Calculate elevation difference
    elevation_diff = dem - daymet_elevation  # meters
    
    # Apply lapse rate
    temp_adjusted = temp_daymet + (lapse_rate * elevation_diff / 1000)
    
    return temp_adjusted
```

## Precipitation Processing

### Effective Precipitation

Effective precipitation is the portion available for subsurface processes after evapotranspiration:

$$P_{eff} = P_{total} - ET$$

The framework calculates ET using multiple methods:

#### Hamon Method (Simple)

```python
def calculate_pet_hamon(temp_mean, daylight_hours):
    """
    Hamon (1963) potential evapotranspiration
    
    Simple temperature-based method
    """
    
    # Saturated vapor pressure at mean temperature
    es = 0.6108 * exp(17.27 * temp_mean / (temp_mean + 237.3))  # kPa
    
    # Hamon coefficient
    k = 0.55  # Empirical constant
    
    # PET in mm/day
    pet = k * (daylight_hours / 12) * (es / (temp_mean + 273.15)) * 25.4
    
    return pet
```

#### Priestley-Taylor Method (Energy-based)

```python
def calculate_pet_priestley_taylor(net_radiation, temp_mean):
    """
    Priestley-Taylor (1972) potential evapotranspiration
    
    Requires radiation data
    """
    
    # Psychrometric constant
    gamma = 0.665  # kPa/°C at sea level
    
    # Slope of saturation vapor pressure curve
    delta = 4098 * (0.6108 * exp(17.27 * temp_mean / (temp_mean + 237.3))) / (temp_mean + 237.3)**2
    
    # Priestley-Taylor coefficient
    alpha = 1.26  # For wet surfaces
    
    # Latent heat of vaporization
    lambda_v = 2.45  # MJ/kg
    
    # PET in mm/day
    pet = alpha * (delta / (delta + gamma)) * (net_radiation / lambda_v)
    
    return pet
```

### Precipitation Phase Partitioning

Determining rain vs. snow based on temperature:

```python
def partition_precipitation(precip, temp):
    """
    Partition precipitation into rain and snow
    
    Based on USACE (1956) method with improvements
    """
    
    # Temperature thresholds
    T_rain = 3.0   # All rain above this temperature (°C)
    T_snow = -1.0  # All snow below this temperature (°C)
    
    if temp >= T_rain:
        rain = precip
        snow = 0
    elif temp <= T_snow:
        rain = 0
        snow = precip
    else:
        # Linear transition zone
        rain_fraction = (temp - T_snow) / (T_rain - T_snow)
        rain = precip * rain_fraction
        snow = precip * (1 - rain_fraction)
    
    return rain, snow
```

## Vapor Pressure Processing

### Humidity Calculations

DAYMET provides vapor pressure (VP) which can be converted to other humidity metrics:

```python
def calculate_humidity_metrics(vp, temp):
    """
    Calculate various humidity metrics from vapor pressure
    
    Parameters:
    - vp: Vapor pressure (Pa)
    - temp: Temperature (°C)
    
    Returns:
    - Dictionary of humidity metrics
    """
    
    # Saturation vapor pressure
    es = 611 * exp(17.27 * temp / (temp + 237.3))  # Pa
    
    # Relative humidity
    rh = (vp / es) * 100  # Percent
    
    # Specific humidity
    pressure = 101325  # Pa (sea level standard)
    q = 0.622 * vp / (pressure - 0.378 * vp)  # kg/kg
    
    # Vapor pressure deficit
    vpd = es - vp  # Pa
    
    # Dewpoint temperature (Magnus formula inverse)
    if vp > 0:
        dewpoint = 237.3 * log(vp / 611) / (17.27 - log(vp / 611))
    else:
        dewpoint = -273.15  # Invalid
    
    return {
        'relative_humidity': rh,
        'specific_humidity': q,
        'vapor_pressure_deficit': vpd,
        'dewpoint_temperature': dewpoint
    }
```

## Projection Alignment

### Coordinate System Transformation

DAYMET uses Lambert Conformal Conic projection, which must be aligned with DEM data:

```python
def reproject_daymet_to_dem(daymet_file, dem_file, output_file):
    """
    Reproject DAYMET data to match DEM coordinate system
    """
    
    import rasterio
    from rasterio.warp import calculate_default_transform, reproject
    
    # Open source and destination
    with rasterio.open(daymet_file) as src:
        with rasterio.open(dem_file) as dem:
            
            # Calculate transform
            transform, width, height = calculate_default_transform(
                src.crs,
                dem.crs,
                dem.width,
                dem.height,
                *dem.bounds
            )
            
            # Update profile
            profile = dem.profile.copy()
            profile.update({
                'transform': transform,
                'crs': dem.crs,
                'width': width,
                'height': height
            })
            
            # Reproject
            with rasterio.open(output_file, 'w', **profile) as dst:
                for band_idx in range(1, src.count + 1):
                    reproject(
                        source=rasterio.band(src, band_idx),
                        destination=rasterio.band(dst, band_idx),
                        src_transform=src.transform,
                        src_crs=src.crs,
                        dst_transform=transform,
                        dst_crs=dem.crs,
                        resampling=rasterio.enums.Resampling.bilinear
                    )
    
    return output_file
```

### Spatial Interpolation

When DAYMET resolution (1 km) differs from DEM resolution:

```python
def interpolate_climate_to_dem(climate_data, dem, method='bilinear'):
    """
    Interpolate climate data to DEM resolution
    
    Methods:
    - 'bilinear': Smooth interpolation (default)
    - 'cubic': Smoother interpolation
    - 'nearest': Preserve exact values
    - 'kriging': Geostatistical interpolation
    """
    
    from scipy.interpolate import RegularGridInterpolator
    
    if method in ['bilinear', 'cubic', 'nearest']:
        # Simple interpolation
        interp_func = RegularGridInterpolator(
            (climate_data.y, climate_data.x),
            climate_data.values,
            method=method,
            bounds_error=False,
            fill_value=None
        )
        
        # Create DEM grid
        dem_points = np.stack(
            np.meshgrid(dem.y, dem.x, indexing='ij'),
            axis=-1
        )
        
        # Interpolate
        interpolated = interp_func(dem_points)
        
    elif method == 'kriging':
        # Geostatistical interpolation
        from pykrige import OrdinaryKriging
        
        ok = OrdinaryKriging(
            climate_data.x.flatten(),
            climate_data.y.flatten(),
            climate_data.values.flatten(),
            variogram_model='spherical'
        )
        
        interpolated, variance = ok.execute(
            'grid',
            dem.x,
            dem.y
        )
    
    return interpolated
```

## Temporal Aggregation

### Monthly Summaries

Converting daily DAYMET data to monthly values:

```python
def aggregate_daymet_monthly(daily_data, variable, year):
    """
    Aggregate daily DAYMET to monthly values
    
    Aggregation method depends on variable:
    - Temperature: mean
    - Precipitation: sum
    - Vapor pressure: mean
    - Radiation: mean or sum
    """
    
    import pandas as pd
    
    # Create date index
    dates = pd.date_range(f'{year}-01-01', f'{year}-12-31', freq='D')
    
    # Convert to xarray with time dimension
    data_with_time = xr.DataArray(
        daily_data,
        dims=['time', 'y', 'x'],
        coords={'time': dates}
    )
    
    # Aggregation rules
    aggregation_rules = {
        'tmin': 'mean',
        'tmax': 'mean',
        'prcp': 'sum',
        'vp': 'mean',
        'srad': 'mean',
        'swe': 'mean'
    }
    
    # Apply aggregation
    method = aggregation_rules.get(variable, 'mean')
    
    if method == 'sum':
        monthly = data_with_time.resample(time='1M').sum()
    else:
        monthly = data_with_time.resample(time='1M').mean()
    
    return monthly
```

### Annual Climatologies

Creating long-term climate normals:

```python
def calculate_climate_normals(start_year, end_year, variable, bbox):
    """
    Calculate 30-year climate normals
    
    Standard periods:
    - 1981-2010
    - 1991-2020
    """
    
    all_data = []
    
    for year in range(start_year, end_year + 1):
        yearly_data = get_daymet_subset(bbox, year, [variable])
        all_data.append(yearly_data)
    
    # Stack years
    stacked = np.stack(all_data, axis=0)
    
    # Calculate statistics
    normals = {
        'mean': np.mean(stacked, axis=0),
        'std': np.std(stacked, axis=0),
        'min': np.min(stacked, axis=0),
        'max': np.max(stacked, axis=0),
        'percentile_10': np.percentile(stacked, 10, axis=0),
        'percentile_90': np.percentile(stacked, 90, axis=0)
    }
    
    return normals
```

## Quality Control

### Data Validation

```python
def validate_climate_data(data, variable):
    """
    Quality control for climate data
    """
    
    # Physical limits
    limits = {
        'tmin': (-60, 50),    # °C
        'tmax': (-50, 60),    # °C
        'prcp': (0, 500),      # mm/day
        'vp': (0, 10000),      # Pa
        'srad': (0, 1000),     # W/m²
    }
    
    # Check range
    vmin, vmax = limits.get(variable, (-np.inf, np.inf))
    out_of_range = (data < vmin) | (data > vmax)
    
    if np.any(out_of_range):
        print(f"Warning: {np.sum(out_of_range)} values out of range for {variable}")
        
    # Check for missing data
    missing = np.isnan(data)
    if np.any(missing):
        print(f"Warning: {np.sum(missing)} missing values for {variable}")
    
    # Check temporal consistency
    if len(data.shape) > 2:  # Has time dimension
        # Check for unrealistic jumps
        daily_diff = np.diff(data, axis=0)
        max_change = {
            'tmin': 20,  # °C/day
            'tmax': 20,  # °C/day
            'prcp': 200  # mm/day
        }
        
        threshold = max_change.get(variable, np.inf)
        jumps = np.abs(daily_diff) > threshold
        if np.any(jumps):
            print(f"Warning: {np.sum(jumps)} unrealistic daily changes for {variable}")
    
    return {
        'out_of_range': np.sum(out_of_range),
        'missing': np.sum(missing),
        'suspicious_changes': np.sum(jumps) if len(data.shape) > 2 else 0
    }
```

## Alternative Climate Datasets

### PRISM

```python
def get_prism_data(bbox, year_month, variable):
    """
    Alternative: PRISM climate data (CONUS only)
    4km resolution, 1895-present
    """
    
    base_url = "http://services.nacse.org/prism/data/public/4km"
    
    # Variable codes
    var_codes = {
        'ppt': 'ppt',    # Precipitation
        'tmean': 'tmean', # Mean temperature
        'tmin': 'tmin',   # Minimum temperature
        'tmax': 'tmax',   # Maximum temperature
        'tdmean': 'tdmean', # Mean dewpoint
        'vpdmin': 'vpdmin', # Minimum VPD
        'vpdmax': 'vpdmax'  # Maximum VPD
    }
    
    # Download and process
    # Implementation details...
```

### ERA5

```python
def get_era5_data(bbox, date_range, variables):
    """
    Alternative: ERA5 reanalysis (global)
    0.25° resolution (~28 km), 1979-present
    Hourly data available
    """
    
    import cdsapi
    
    client = cdsapi.Client()
    
    request = {
        'product_type': 'reanalysis',
        'format': 'netcdf',
        'variable': variables,
        'year': date_range.year,
        'month': date_range.month,
        'day': date_range.day,
        'time': ['00:00', '06:00', '12:00', '18:00'],
        'area': [bbox[3], bbox[0], bbox[1], bbox[2]],  # N, W, S, E
    }
    
    # Download from Copernicus Climate Data Store
    # Implementation details...
```

## References

- Thornton, P. E., et al. (2020). Daymet: Daily Surface Weather Data on a 1-km Grid for North America, Version 4. *ORNL DAAC*.

- Hamon, W. R. (1963). Computation of direct runoff amounts from storm rainfall. *International Association of Scientific Hydrology Publication*, 63, 52-62.

- Priestley, C. H. B., & Taylor, R. J. (1972). On the assessment of surface heat flux and evaporation using large-scale parameters. *Monthly Weather Review*, 100(2), 81-92.

---

*Next: [Topographic Analysis →](topographic-analysis.md)*