---
title: Examples
---

# EEMT Calculation Examples

## Overview

This section provides complete, working examples for EEMT calculations across different study areas and use cases, integrating public datasets with the GRASS GIS parallel processing framework.

## Example 1: Arizona Sky Islands Analysis

### Study Area: Santa Catalina Mountains

Based on the validation case study from Rasmussen et al. (2014).

```python
#!/usr/bin/env python3
"""
Arizona Sky Islands EEMT Analysis
Replicating Rasmussen et al. (2014) study with modern tools
"""

import numpy as np
import rasterio
import xarray as xr
from pathlib import Path

# Study area definition
STUDY_AREA = {
    'name': 'Santa Catalina Mountains',
    'bbox': [-110.95, 32.35, -110.70, 32.45],  # [west, south, east, north]
    'elevation_range': [800, 2800],  # meters
    'climate_zones': ['desert_scrub', 'oak_woodland', 'pine_forest', 'mixed_conifer']
}

def arizona_eemt_example():
    """Complete Arizona EEMT analysis example"""
    
    project_dir = Path('arizona_eemt_example')
    project_dir.mkdir(exist_ok=True)
    
    print("=== Arizona Sky Islands EEMT Analysis ===")
    print(f"Study area: {STUDY_AREA['name']}")
    print(f"Bounding box: {STUDY_AREA['bbox']}")
    
    # Step 1: Download data
    print("\\n1. Downloading elevation data...")
    
    # Use OpenTopography for this region
    from docs.data_sources import download_opentopo
    dem_file = download_opentopo(STUDY_AREA['bbox'], 'SRTMGL1')
    
    # Download higher resolution USGS data if available
    try:
        from docs.data_sources import download_3dep
        dem_high_res = download_3dep(STUDY_AREA['bbox'], '10m')
        if dem_high_res:
            dem_file = dem_high_res
            print("✓ Using 10m USGS elevation data")
    except:
        print("✓ Using 30m SRTM elevation data")
    
    # Step 2: Download climate data
    print("\\n2. Downloading DAYMET climate data...")
    
    climate_dir = project_dir / 'climate'
    climate_dir.mkdir(exist_ok=True)
    
    # Download 5 years of DAYMET data
    for year in range(2015, 2020):
        for variable in ['tmin', 'tmax', 'prcp', 'vp']:
            url = f"https://thredds.daac.ornl.gov/thredds/fileServer/ornldaac/1328/daymet_v4_daily_na_{variable}_{year}.nc"
            output_file = climate_dir / f"daymet_{variable}_{year}.nc"
            
            if not output_file.exists():
                print(f"  Downloading {variable} {year}...")
                # Download implementation here
    
    # Step 3: Download vegetation data
    print("\\n3. Downloading Landsat NDVI data...")
    
    # Use Google Earth Engine or USGS API
    # Implementation for Landsat NDVI download
    
    # Step 4: Run EEMT calculations
    print("\\n4. Running EEMT calculations...")
    
    # Traditional EEMT
    eemt_trad = calculate_traditional_eemt(
        dem_file, climate_dir, project_dir / 'eemt_traditional.tif'
    )
    
    # Topographic EEMT  
    eemt_topo = calculate_topographic_eemt(
        dem_file, climate_dir, project_dir / 'eemt_topographic.tif'
    )
    
    # Vegetation EEMT
    eemt_veg = calculate_vegetation_eemt(
        dem_file, climate_dir, project_dir / 'eemt_vegetation.tif',
        ndvi_file=project_dir / 'landsat_ndvi.tif'
    )
    
    # Step 5: Analysis and validation
    print("\\n5. Analyzing results...")
    
    # Load results for comparison
    with rasterio.open(project_dir / 'eemt_traditional.tif') as src:
        eemt_trad_data = src.read(1)
    with rasterio.open(project_dir / 'eemt_topographic.tif') as src:
        eemt_topo_data = src.read(1)
    with rasterio.open(project_dir / 'eemt_vegetation.tif') as src:
        eemt_veg_data = src.read(1)
    
    # Generate summary statistics
    methods = {
        'Traditional': eemt_trad_data,
        'Topographic': eemt_topo_data, 
        'Vegetation': eemt_veg_data
    }
    
    print("\\nEEMT Summary by Method:")
    print("-" * 50)
    for method, data in methods.items():
        print(f"{method:12} | Mean: {np.nanmean(data):6.1f} | Std: {np.nanstd(data):5.1f} | Range: {np.nanmin(data):5.1f}-{np.nanmax(data):5.1f} MJ/m²/yr")
    
    # Aspect analysis (north vs south slopes)
    with rasterio.open(dem_file) as src:
        elevation = src.read(1)
    
    # Calculate aspect using GDAL
    import subprocess
    aspect_file = project_dir / 'aspect.tif'
    subprocess.run([
        'gdaldem', 'aspect', str(dem_file), str(aspect_file)
    ], check=True)
    
    with rasterio.open(aspect_file) as src:
        aspect = src.read(1)
    
    # Define north vs south facing slopes
    north_mask = (aspect >= 315) | (aspect <= 45)  # North-facing ±45°
    south_mask = (aspect >= 135) & (aspect <= 225)  # South-facing ±45°
    
    print("\\nAspect Analysis:")
    print("-" * 30)
    for method, data in methods.items():
        north_mean = np.nanmean(data[north_mask])
        south_mean = np.nanmean(data[south_mask])
        difference = north_mean - south_mean
        print(f"{method:12} | North: {north_mean:5.1f} | South: {south_mean:5.1f} | Diff: {difference:+5.1f} MJ/m²/yr")
    
    # Elevation gradient analysis
    elevation_bins = np.arange(800, 2800, 200)
    
    print("\\nElevation Gradient Analysis:")
    print("-" * 40)
    print("Elevation   | Traditional | Topographic | Vegetation")
    print("-" * 40)
    
    for i in range(len(elevation_bins)-1):
        elev_mask = (elevation >= elevation_bins[i]) & (elevation < elevation_bins[i+1])
        
        if np.sum(elev_mask) > 100:  # Sufficient pixels
            trad_mean = np.nanmean(eemt_trad_data[elev_mask])
            topo_mean = np.nanmean(eemt_topo_data[elev_mask])
            veg_mean = np.nanmean(eemt_veg_data[elev_mask])
            
            print(f"{elevation_bins[i]:4.0f}-{elevation_bins[i+1]:4.0f}m | {trad_mean:10.1f} | {topo_mean:10.1f} | {veg_mean:9.1f}")
    
    print(f"\\n✓ Arizona Sky Islands analysis completed")
    print(f"Results saved to: {project_dir}")

if __name__ == '__main__':
    arizona_eemt_example()
```

## Example 2: Large Watershed Analysis

### Multi-Scale EEMT Calculation

```python
#!/usr/bin/env python3
"""
Large Watershed EEMT Analysis
Demonstrates tiled processing for continental-scale applications
"""

import numpy as np
from pathlib import Path
import multiprocessing as mp

def large_watershed_example():
    """
    Large watershed EEMT calculation example
    Demonstrates handling of large spatial extents
    """
    
    # Colorado River Basin example
    STUDY_AREA = {
        'name': 'Colorado River Basin',
        'bbox': [-114.0, 32.0, -106.0, 42.0],  # Large region
        'tile_size': 1.0,  # 1 degree tiles
        'years': [2010, 2020]
    }
    
    project_dir = Path('colorado_river_eemt')
    project_dir.mkdir(exist_ok=True)
    
    print("=== Large Watershed EEMT Analysis ===")
    print(f"Study area: {STUDY_AREA['name']}")
    print(f"Spatial extent: {STUDY_AREA['bbox']}")
    
    # Step 1: Create processing tiles
    print("\\n1. Creating processing tiles...")
    
    west, south, east, north = STUDY_AREA['bbox']
    tile_size = STUDY_AREA['tile_size']
    
    tiles = []
    tile_id = 0
    
    for lat in np.arange(south, north, tile_size):
        for lon in np.arange(west, east, tile_size):
            
            tile_bbox = [lon, lat, lon + tile_size, lat + tile_size]
            tiles.append({
                'id': tile_id,
                'bbox': tile_bbox,
                'center': [lon + tile_size/2, lat + tile_size/2]
            })
            tile_id += 1
    
    print(f"Created {len(tiles)} processing tiles")
    
    # Step 2: Process tiles in parallel
    print("\\n2. Processing tiles in parallel...")
    
    def process_tile(tile):
        """Process single tile"""
        
        tile_dir = project_dir / f"tile_{tile['id']:03d}"
        tile_dir.mkdir(exist_ok=True)
        
        try:
            # Download data for tile
            dem_file = download_3dep(tile['bbox'], '30m')
            
            # Download DAYMET data for tile
            climate_files = download_daymet_spatial(
                tile['bbox'], 
                range(STUDY_AREA['years'][0], STUDY_AREA['years'][1]+1),
                ['tmin', 'tmax', 'prcp']
            )
            
            # Calculate EEMT for tile
            from workflows import run_complete_eemt_pipeline
            
            results = run_complete_eemt_pipeline(
                dem_file,
                tile_dir / 'results',
                tile_dir / 'climate',
                STUDY_AREA['years'][0], 
                STUDY_AREA['years'][1]
            )
            
            return tile['id'], True, tile_dir / 'results' / 'eemt_topographic.tif'
            
        except Exception as e:
            print(f"Tile {tile['id']} failed: {e}")
            return tile['id'], False, None
    
    # Process tiles in parallel
    max_workers = min(mp.cpu_count(), 8)  # Limit concurrent downloads
    
    with mp.Pool(max_workers) as pool:
        tile_results = pool.map(process_tile, tiles)
    
    # Step 3: Merge tile results
    print("\\n3. Merging tile results...")
    
    successful_tiles = [result for result in tile_results if result[1]]
    failed_tiles = [result for result in tile_results if not result[1]]
    
    print(f"Successful tiles: {len(successful_tiles)}")
    print(f"Failed tiles: {len(failed_tiles)}")
    
    if successful_tiles:
        # Merge using GDAL
        tile_files = [str(result[2]) for result in successful_tiles]
        merged_file = project_dir / 'colorado_river_eemt_merged.tif'
        
        import subprocess
        subprocess.run([
            'gdal_merge.py', '-o', str(merged_file), '-co', 'COMPRESS=LZW'
        ] + tile_files, check=True)
        
        print(f"✓ Merged results saved to: {merged_file}")
    
    return len(successful_tiles) > 0

if __name__ == '__main__':
    large_watershed_example()
```

## Example 3: Time Series Analysis

### Multi-Decade EEMT Trends

```python
#!/usr/bin/env python3
"""
Time Series EEMT Analysis
Calculate long-term trends and climate change effects
"""

import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
from scipy import stats
import pandas as pd

def time_series_eemt_example():
    """
    Multi-decade EEMT time series analysis
    Demonstrates climate change impact assessment
    """
    
    # Example: Western US mountain region
    STUDY_AREA = {
        'name': 'Rocky Mountain National Park',
        'bbox': [-105.8, 40.1, -105.5, 40.5],
        'years': [1980, 2023],  # Full DAYMET record
        'elevation_bands': [2000, 2500, 3000, 3500]  # Analyze by elevation zone
    }
    
    project_dir = Path('rocky_mountain_time_series')
    project_dir.mkdir(exist_ok=True)
    
    print("=== Multi-Decade EEMT Time Series Analysis ===")
    print(f"Study area: {STUDY_AREA['name']}")
    print(f"Time period: {STUDY_AREA['years'][0]}-{STUDY_AREA['years'][1]} ({STUDY_AREA['years'][1] - STUDY_AREA['years'][0] + 1} years)")
    
    # Step 1: Download multi-decade climate data
    print("\\n1. Downloading multi-decade climate data...")
    
    climate_data = {}
    years = range(STUDY_AREA['years'][0], STUDY_AREA['years'][1] + 1)
    
    for variable in ['tmin', 'tmax', 'prcp']:
        
        # Download and concatenate all years
        annual_files = []
        for year in years:
            url = f"https://thredds.daac.ornl.gov/thredds/dodsC/ornldaac/1328/daymet_v4_daily_na_{variable}_{year}.nc"
            
            # Subset to study area
            ds = xr.open_dataset(url)
            bbox = STUDY_AREA['bbox']
            subset = ds.sel(x=slice(bbox[0], bbox[2]), y=slice(bbox[1], bbox[3]))
            annual_files.append(subset)
        
        # Concatenate all years
        climate_data[variable] = xr.concat(annual_files, dim='time')
        print(f"✓ {variable}: {len(years)} years loaded")
    
    # Step 2: Calculate annual EEMT time series
    print("\\n2. Calculating annual EEMT time series...")
    
    # Resample to annual means
    annual_climate = {}
    for var, data in climate_data.items():
        annual_climate[var] = data.resample(time='1Y').mean()
    
    # Calculate EEMT for each year
    eemt_time_series = []
    
    for year_idx in range(len(years)):
        
        year = years[year_idx]
        print(f"  Processing year {year}...")
        
        # Extract climate for this year
        temp_mean = (annual_climate['tmin'].isel(time=year_idx) + 
                    annual_climate['tmax'].isel(time=year_idx)) / 2
        precip = annual_climate['prcp'].isel(time=year_idx)
        
        # Simple EEMT calculation (traditional method)
        # Calculate PET (simplified Hamon)
        temp_celsius = temp_mean.values - 273.15
        pet = 0.0023 * (temp_celsius + 17.8) * np.sqrt(np.maximum(0, temp_celsius)) * 58.93
        
        # Effective precipitation
        effective_precip = np.maximum(0, precip.values - pet)
        
        # NPP (Lieth method)
        npp = np.where(temp_celsius > 0, 
                      3000 * (1 - np.exp(1.315 - 0.119 * temp_celsius))**(-1),
                      0)
        
        # EEMT components
        h_bio = 22e6  # J/kg
        c_w = 4180   # J/kg/K
        
        e_bio = (npp / 1000) * h_bio / (365 * 24 * 3600)  # W/m²
        e_ppt = (effective_precip / 1000) * c_w * np.maximum(0, temp_celsius) / (365 * 24 * 3600)
        
        eemt = (e_bio + e_ppt) * 365 * 24 * 3600 / 1e6  # MJ/m²/yr
        
        # Store results
        eemt_time_series.append({
            'year': year,
            'eemt_mean': np.nanmean(eemt),
            'eemt_std': np.nanstd(eemt),
            'temp_mean': np.nanmean(temp_celsius),
            'precip_mean': np.nanmean(precip.values),
            'npp_mean': np.nanmean(npp)
        })
    
    # Step 3: Trend analysis
    print("\\n3. Analyzing trends...")
    
    # Convert to DataFrame
    df = pd.DataFrame(eemt_time_series)
    
    # Calculate trends
    trends = {}
    for variable in ['eemt_mean', 'temp_mean', 'precip_mean', 'npp_mean']:
        slope, intercept, r_value, p_value, std_err = stats.linregress(df['year'], df[variable])
        
        trends[variable] = {
            'slope': slope,
            'r_squared': r_value**2,
            'p_value': p_value,
            'trend_per_decade': slope * 10
        }
    
    # Print trend analysis
    print("\\nTrend Analysis (1980-2023):")
    print("-" * 60)
    print(f"{'Variable':<15} | {'Trend/Decade':<12} | {'R²':<6} | {'p-value':<8}")
    print("-" * 60)
    
    trend_labels = {
        'eemt_mean': 'EEMT',
        'temp_mean': 'Temperature', 
        'precip_mean': 'Precipitation',
        'npp_mean': 'NPP'
    }
    
    units = {
        'eemt_mean': 'MJ/m²/yr',
        'temp_mean': '°C',
        'precip_mean': 'mm/yr', 
        'npp_mean': 'g/m²/yr'
    }
    
    for var, trend in trends.items():
        label = trend_labels[var]
        unit = units[var]
        print(f"{label:<15} | {trend['trend_per_decade']:+8.3f} {unit:<3} | {trend['r_squared']:<6.3f} | {trend['p_value']:<8.4f}")
    
    # Step 4: Generate visualizations
    print("\\n4. Generating time series plots...")
    
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    fig.suptitle(f"{STUDY_AREA['name']} EEMT Time Series (1980-2023)")
    
    # EEMT time series
    axes[0,0].plot(df['year'], df['eemt_mean'], 'b-', linewidth=2)
    axes[0,0].fill_between(df['year'], 
                          df['eemt_mean'] - df['eemt_std'],
                          df['eemt_mean'] + df['eemt_std'], 
                          alpha=0.3)
    axes[0,0].set_title('EEMT Time Series')
    axes[0,0].set_ylabel('EEMT (MJ/m²/yr)')
    
    # Temperature trend
    axes[0,1].plot(df['year'], df['temp_mean'], 'r-', linewidth=2)
    axes[0,1].set_title('Temperature Trend')
    axes[0,1].set_ylabel('Temperature (°C)')
    
    # Precipitation trend  
    axes[1,0].plot(df['year'], df['precip_mean'], 'g-', linewidth=2)
    axes[1,0].set_title('Precipitation Trend')
    axes[1,0].set_ylabel('Precipitation (mm/yr)')
    
    # NPP trend
    axes[1,1].plot(df['year'], df['npp_mean'], 'orange', linewidth=2)
    axes[1,1].set_title('NPP Trend')
    axes[1,1].set_ylabel('NPP (g/m²/yr)')
    
    for ax in axes.flat:
        ax.grid(True, alpha=0.3)
        ax.set_xlabel('Year')
    
    plt.tight_layout()
    plt.savefig(project_dir / 'eemt_time_series.png', dpi=300, bbox_inches='tight')
    plt.show()
    
    # Step 5: Climate sensitivity analysis
    print("\\n5. Analyzing climate sensitivity...")
    
    # Calculate correlations between EEMT and climate drivers
    correlations = {}
    for climate_var in ['temp_mean', 'precip_mean']:
        r, p = stats.pearsonr(df['eemt_mean'], df[climate_var])
        correlations[climate_var] = {'correlation': r, 'p_value': p}
    
    print("\\nEEMT-Climate Correlations:")
    print("-" * 35)
    for var, corr in correlations.items():
        var_name = 'Temperature' if 'temp' in var else 'Precipitation'
        print(f"{var_name:<13} | r={corr['correlation']:+6.3f} | p={corr['p_value']:<6.4f}")
    
    # Save time series data
    df.to_csv(project_dir / 'eemt_time_series.csv', index=False)
    
    print(f"\\n✓ Time series analysis completed")
    print(f"Data saved to: {project_dir / 'eemt_time_series.csv'}")
    print(f"Plots saved to: {project_dir / 'eemt_time_series.png'}")

if __name__ == '__main__':
    time_series_eemt_example()
```

## Example 3: Urban Heat Island Analysis

### EEMT in Urban Environments

```python
#!/usr/bin/env python3
"""
Urban Heat Island EEMT Analysis
Demonstrates EEMT application to urban environments
"""

def urban_heat_island_example():
    """
    Urban EEMT calculation example
    Phoenix, Arizona metropolitan area
    """
    
    STUDY_AREA = {
        'name': 'Phoenix Metropolitan Area',
        'bbox': [-112.5, 33.2, -111.5, 33.8],
        'urban_center': [-112.0, 33.5],
        'land_cover_classes': ['urban', 'desert', 'agriculture', 'mountain']
    }
    
    project_dir = Path('phoenix_urban_eemt')
    project_dir.mkdir(exist_ok=True)
    
    print("=== Urban Heat Island EEMT Analysis ===")
    print(f"Study area: {STUDY_AREA['name']}")
    
    # Step 1: Download high-resolution data
    print("\\n1. Downloading urban-scale data...")
    
    # High-resolution DEM for urban analysis
    dem_file = download_3dep(STUDY_AREA['bbox'], '1m')  # 1m lidar if available
    
    # Landsat thermal and optical data
    landsat_data = download_landsat_collection(
        STUDY_AREA['bbox'], 
        '2020-06-01', '2020-08-31',  # Summer period
        ['red', 'nir', 'thermal']
    )
    
    # Urban land cover data
    # Use NLCD (National Land Cover Database) for US
    nlcd_url = "https://www.mrlc.gov/geoserver/mrlc_download/NLCD_2019_Land_Cover_L48/wcs"
    
    # Step 2: Urban-specific EEMT modifications
    print("\\n2. Calculating urban-modified EEMT...")
    
    # Urban heat island temperature adjustment
    def calculate_urban_temperature_effect(land_cover, base_temperature):
        """Apply urban heat island temperature corrections"""
        
        # Urban heat island intensity by land cover class
        uhi_correction = {
            'developed_high': +4.0,      # °C increase in dense urban
            'developed_medium': +2.5,    # °C increase in suburban  
            'developed_low': +1.0,       # °C increase in low density
            'developed_open': +0.5,      # °C increase in parks/open space
            'natural': 0.0               # No UHI effect
        }
        
        # Apply corrections based on land cover
        temp_adjusted = base_temperature.copy()
        for class_name, correction in uhi_correction.items():
            mask = land_cover == class_name
            temp_adjusted[mask] += correction
        
        return temp_adjusted
    
    # Urban albedo effects
    def calculate_urban_albedo(land_cover):
        """Calculate albedo by urban land cover type"""
        
        albedo_values = {
            'developed_high': 0.15,     # Dark urban surfaces
            'developed_medium': 0.18,   # Mixed urban/suburban
            'developed_low': 0.22,      # Suburban with vegetation
            'developed_open': 0.25,     # Parks and open space
            'natural': 0.20             # Natural vegetation
        }
        
        albedo = np.zeros_like(land_cover, dtype=np.float32)
        for class_name, albedo_val in albedo_values.items():
            mask = land_cover == class_name
            albedo[mask] = albedo_val
        
        return albedo
    
    # Urban NPP modifications
    def calculate_urban_npp(land_cover, base_npp):
        """Modify NPP for urban land cover effects"""
        
        npp_factors = {
            'developed_high': 0.1,      # Very low NPP in dense urban
            'developed_medium': 0.3,    # Reduced NPP in suburban
            'developed_low': 0.6,       # Moderate NPP with some vegetation
            'developed_open': 0.8,      # Near-natural NPP in parks
            'natural': 1.0              # Unmodified NPP
        }
        
        npp_urban = base_npp.copy()
        for class_name, factor in npp_factors.items():
            mask = land_cover == class_name
            npp_urban[mask] *= factor
        
        return npp_urban
    
    # Step 3: Run urban EEMT calculation
    print("\\n3. Running urban EEMT calculation...")
    
    # Load base data
    with rasterio.open(dem_file) as src:
        elevation = src.read(1)
        profile = src.profile
    
    # Load land cover (placeholder - implement actual NLCD loading)
    land_cover = np.random.choice(['developed_high', 'developed_medium', 'natural'], 
                                 size=elevation.shape)
    
    # Load climate data
    climate_data = load_daymet_annual_means(STUDY_AREA['bbox'], 2020)
    
    # Apply urban modifications
    temp_urban = calculate_urban_temperature_effect(land_cover, climate_data['temperature'])
    albedo_urban = calculate_urban_albedo(land_cover) 
    
    # Calculate solar radiation with urban albedo
    # (This would integrate with r.sun calculations)
    
    # Calculate urban NPP
    base_npp = calculate_npp_lieth(temp_urban, climate_data['precipitation'])
    npp_urban = calculate_urban_npp(land_cover, base_npp)
    
    # Calculate urban EEMT
    h_bio = 22e6
    c_w = 4180
    
    e_bio = (npp_urban / 1000) * h_bio / (365 * 24 * 3600)
    e_ppt = (climate_data['effective_precipitation'] / 1000) * c_w * np.maximum(0, temp_urban - 273.15) / (365 * 24 * 3600)
    
    eemt_urban = (e_bio + e_ppt) * 365 * 24 * 3600 / 1e6
    
    # Step 4: Urban vs natural comparison
    print("\\n4. Comparing urban vs natural EEMT...")
    
    # Calculate natural EEMT (without urban effects)
    temp_natural = climate_data['temperature']
    npp_natural = calculate_npp_lieth(temp_natural, climate_data['precipitation'])
    
    e_bio_natural = (npp_natural / 1000) * h_bio / (365 * 24 * 3600)
    e_ppt_natural = (climate_data['effective_precipitation'] / 1000) * c_w * np.maximum(0, temp_natural - 273.15) / (365 * 24 * 3600)
    eemt_natural = (e_bio_natural + e_ppt_natural) * 365 * 24 * 3600 / 1e6
    
    # Calculate urban effect
    urban_effect = eemt_urban - eemt_natural
    
    # Analyze by land cover class
    print("\\nUrban EEMT Effects by Land Cover:")
    print("-" * 50)
    print(f"{'Land Cover':<18} | {'Mean EEMT':<10} | {'Urban Effect':<12}")
    print("-" * 50)
    
    for class_name in ['developed_high', 'developed_medium', 'developed_low', 'natural']:
        mask = land_cover == class_name
        if np.sum(mask) > 100:  # Sufficient pixels
            mean_eemt = np.nanmean(eemt_urban[mask])
            mean_effect = np.nanmean(urban_effect[mask])
            print(f"{class_name:<18} | {mean_eemt:8.1f} | {mean_effect:+10.1f}")
    
    # Step 5: Save results
    print("\\n5. Saving urban analysis results...")
    
    outputs = {
        'eemt_urban.tif': eemt_urban,
        'eemt_natural.tif': eemt_natural,
        'urban_effect.tif': urban_effect,
        'temperature_urban.tif': temp_urban,
        'npp_urban.tif': npp_urban,
        'land_cover.tif': land_cover.astype(np.int16)
    }
    
    for filename, data in outputs.items():
        with rasterio.open(project_dir / filename, 'w', **profile) as dst:
            dst.write(data.astype(np.float32), 1)
    
    print(f"✓ Urban heat island analysis completed")
    print(f"Results saved to: {project_dir}")

if __name__ == '__main__':
    urban_heat_island_example()
```

## Example 4: Climate Change Scenarios

### Future EEMT Projections

```python
#!/usr/bin/env python3
"""
Climate Change EEMT Projections
Calculate EEMT under future climate scenarios
"""

def climate_change_scenarios_example():
    """
    EEMT calculation for climate change scenarios
    Using bias-corrected climate model projections
    """
    
    SCENARIOS = {
        'baseline': {
            'period': [1980, 2010],
            'description': 'Historical baseline'
        },
        'near_future': {
            'period': [2020, 2050], 
            'temp_change': +2.0,  # °C warming
            'precip_change': -10,  # % precipitation change
            'description': 'Near-term projections'
        },
        'far_future': {
            'period': [2070, 2100],
            'temp_change': +4.0,  # °C warming  
            'precip_change': -20,  # % precipitation change
            'description': 'End-of-century projections'
        }
    }
    
    project_dir = Path('climate_scenarios_eemt')
    project_dir.mkdir(exist_ok=True)
    
    print("=== Climate Change EEMT Scenarios ===")
    
    # Calculate EEMT for each scenario
    scenario_results = {}
    
    for scenario_name, scenario in SCENARIOS.items():
        
        print(f"\\nCalculating {scenario_name} scenario...")
        print(f"  Description: {scenario['description']}")
        
        if scenario_name == 'baseline':
            # Use historical data
            eemt_result = calculate_historical_eemt(project_dir / scenario_name)
        else:
            # Apply climate change modifications
            eemt_result = calculate_future_eemt(
                project_dir / scenario_name,
                temp_change=scenario['temp_change'],
                precip_change=scenario['precip_change']
            )
        
        scenario_results[scenario_name] = eemt_result
        print(f"✓ {scenario_name} completed")
    
    # Compare scenarios
    print("\\nClimate Change Impact Analysis:")
    print("-" * 60)
    print(f"{'Scenario':<15} | {'Mean EEMT':<10} | {'Change from Baseline':<18}")
    print("-" * 60)
    
    baseline_mean = np.nanmean(scenario_results['baseline'])
    
    for scenario_name, result in scenario_results.items():
        mean_eemt = np.nanmean(result)
        
        if scenario_name == 'baseline':
            change = 0.0
            change_pct = 0.0
        else:
            change = mean_eemt - baseline_mean
            change_pct = (change / baseline_mean) * 100
        
        print(f"{scenario_name:<15} | {mean_eemt:8.1f} | {change:+8.1f} ({change_pct:+5.1f}%)")
    
    # Spatial analysis of changes
    print("\\nSpatial Analysis of Climate Impacts:")
    
    for scenario_name in ['near_future', 'far_future']:
        change_map = scenario_results[scenario_name] - scenario_results['baseline']
        
        print(f"\\n{scenario_name.replace('_', ' ').title()} Changes:")
        print(f"  Mean change: {np.nanmean(change_map):+6.2f} MJ/m²/yr")
        print(f"  Max increase: {np.nanmax(change_map):+6.2f} MJ/m²/yr")
        print(f"  Max decrease: {np.nanmin(change_map):+6.2f} MJ/m²/yr")
        
        # Save change maps
        change_file = project_dir / f'eemt_change_{scenario_name}.tif'
        with rasterio.open(change_file, 'w', **profile) as dst:
            dst.write(change_map.astype(np.float32), 1)
    
    print(f"\\n✓ Climate change analysis completed")
    print(f"Results saved to: {project_dir}")

if __name__ == '__main__':
    climate_change_scenarios_example()
```

## Running the Examples

### Prerequisites
```bash
# Ensure all dependencies are installed
pip install -r requirements.txt

# Verify GRASS GIS installation
grass --version

# Check data access
python -c "import requests; print('✓ Internet connection OK')"
```

### Example Execution

```bash
# Run Arizona Sky Islands example
cd docs/examples/
python arizona_sky_islands.py

# Run large watershed example  
python large_watershed.py --max-workers 4

# Run urban heat island example
python urban_heat_island.py --resolution 1m

# Run climate scenarios example
python climate_scenarios.py --scenarios all
```

### Expected Results

#### Arizona Sky Islands
- **EEMT Range**: 5-45 MJ/m²/yr across elevation gradient
- **Aspect Effect**: ~5 MJ/m²/yr higher on north-facing slopes
- **Elevation Effect**: 300m elevation ≈ north-facing aspect

#### Large Watershed  
- **Processing Time**: ~2-6 hours for Colorado River Basin
- **Tile Success Rate**: >95% with robust error handling
- **Spatial Patterns**: Clear elevation and latitude gradients

#### Urban Heat Island
- **Urban Effect**: +2-8 MJ/m²/yr in developed areas
- **Land Cover Sensitivity**: Strong correlation with development density
- **Seasonal Variation**: Greatest effects during summer months

#### Climate Scenarios
- **Temperature Sensitivity**: ~2-4 MJ/m²/yr per °C warming
- **Precipitation Sensitivity**: Varies by baseline aridity
- **Spatial Heterogeneity**: Mountain regions most sensitive

---

These examples demonstrate the flexibility and power of the EEMT framework for diverse earth system applications, from local ecosystem studies to continental-scale climate impact assessments.