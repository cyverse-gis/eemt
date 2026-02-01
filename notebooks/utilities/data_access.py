"""
Data Access Utilities for EEMT Notebooks
========================================

This module provides functions for downloading and accessing public geospatial
datasets commonly used in EEMT calculations.

Functions:
- download_3dep(): Access USGS 3DEP elevation data
- download_daymet(): Access DAYMET climate data
- download_opentopo(): Access OpenTopography global DEMs
- validate_dataset(): Quality control for downloaded data
"""

import os
import sys
import requests
import numpy as np
import rasterio
from pathlib import Path
import tempfile
import urllib.request
from typing import Tuple, Optional, Dict, List


class DataAccessError(Exception):
    """Custom exception for data access errors"""
    pass


def ensure_output_directory(output_path: str) -> Path:
    """
    Ensure output directory exists
    
    Parameters:
    output_path: Path to output directory
    
    Returns:
    Path object for output directory
    """
    output_dir = Path(output_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def download_sample_dem(output_dir: str = "data/elevation") -> str:
    """
    Download a small sample DEM for testing
    
    Parameters:
    output_dir: Output directory path
    
    Returns:
    Path to downloaded DEM file
    """
    output_dir = ensure_output_directory(output_dir)
    dem_file = output_dir / "sample_dem.tif"
    
    if not dem_file.exists():
        print("Creating synthetic sample DEM...")
        
        # Create synthetic elevation data
        size = 100
        x = np.linspace(0, 10, size)
        y = np.linspace(0, 10, size)
        X, Y = np.meshgrid(x, y)
        
        # Synthetic terrain with realistic elevation values
        elevation = (500 + 200 * np.sin(X) * np.cos(Y) + 
                    100 * np.sin(2*X) * np.sin(3*Y) +
                    50 * np.random.random((size, size)))
        
        # Create GeoTIFF
        from rasterio.transform import from_bounds
        
        transform = from_bounds(-110.5, 32.0, -110.0, 32.5, size, size)
        
        profile = {
            'driver': 'GTiff',
            'height': size,
            'width': size,
            'count': 1,
            'dtype': 'float32',
            'crs': 'EPSG:4326',
            'transform': transform,
            'compress': 'lzw'
        }
        
        with rasterio.open(dem_file, 'w', **profile) as dst:
            dst.write(elevation.astype(np.float32), 1)
        
        print(f"✅ Sample DEM created: {dem_file}")
    
    return str(dem_file)


def download_opentopo_dem(bbox: List[float], dem_type: str = 'SRTMGL1', 
                         output_dir: str = "data/elevation") -> str:
    """
    Download DEM from OpenTopography API
    
    Parameters:
    bbox: [west, south, east, north] in decimal degrees
    dem_type: 'SRTMGL1', 'SRTMGL3', 'ALOS', 'COP30', 'COP90'
    output_dir: Output directory
    
    Returns:
    Path to downloaded DEM file
    """
    output_dir = ensure_output_directory(output_dir)
    
    # Validate bounding box
    west, south, east, north = bbox
    if west >= east or south >= north:
        raise DataAccessError("Invalid bounding box: west >= east or south >= north")
    
    if east - west > 5 or north - south > 5:
        raise DataAccessError("Bounding box too large (>5 degrees). Use smaller area.")
    
    # Construct URL
    base_url = "https://cloud.sdsc.edu/v1/AUTH_opentopography/Raster/API/globaldem"
    
    params = {
        'demtype': dem_type,
        'west': west,
        'south': south,
        'east': east,
        'north': north,
        'outputFormat': 'GTiff'
    }
    
    # Generate filename
    filename = f"{dem_type}_{west}_{south}_{east}_{north}.tif"
    output_file = output_dir / filename
    
    if output_file.exists():
        print(f"✅ DEM already exists: {output_file}")
        return str(output_file)
    
    try:
        print(f"🌍 Downloading {dem_type} DEM for bbox {bbox}...")
        
        response = requests.get(base_url, params=params, timeout=120)
        response.raise_for_status()
        
        # Check if response is actually a GeoTIFF
        if not response.headers.get('content-type', '').startswith('image'):
            raise DataAccessError(f"Invalid response format: {response.headers.get('content-type')}")
        
        with open(output_file, 'wb') as f:
            f.write(response.content)
        
        # Validate the downloaded file
        try:
            with rasterio.open(output_file) as src:
                if src.count == 0:
                    raise DataAccessError("Downloaded file has no data bands")
                
                # Read a small sample to verify data
                sample = src.read(1, window=((0, min(10, src.height)), (0, min(10, src.width))))
                if np.all(np.isnan(sample)):
                    raise DataAccessError("Downloaded file contains only NaN values")
        
        except rasterio.RasterioIOError as e:
            raise DataAccessError(f"Downloaded file is not a valid GeoTIFF: {e}")
        
        print(f"✅ Successfully downloaded: {output_file}")
        return str(output_file)
        
    except requests.exceptions.RequestException as e:
        raise DataAccessError(f"Failed to download DEM: {e}")
    except Exception as e:
        # Clean up partial download
        if output_file.exists():
            output_file.unlink()
        raise DataAccessError(f"Error processing DEM download: {e}")


def download_sample_climate_data(bbox: List[float], year: int = 2020,
                                output_dir: str = "data/climate") -> Dict[str, str]:
    """
    Create sample climate data for testing
    
    Parameters:
    bbox: [west, south, east, north] in decimal degrees
    year: Year for data
    output_dir: Output directory
    
    Returns:
    Dictionary with paths to climate files
    """
    output_dir = ensure_output_directory(output_dir)
    
    # Generate synthetic climate data
    import xarray as xr
    from datetime import datetime, timedelta
    
    # Create coordinate system
    west, south, east, north = bbox
    resolution = 0.01  # ~1km resolution
    
    lons = np.arange(west, east, resolution)
    lats = np.arange(south, north, resolution)
    
    # Create time series for year
    start_date = datetime(year, 1, 1)
    dates = [start_date + timedelta(days=i) for i in range(365)]
    
    # Synthetic climate patterns
    lon_grid, lat_grid = np.meshgrid(lons, lats)
    
    climate_files = {}
    
    for variable in ['tmin', 'tmax', 'prcp']:
        filename = f"sample_{variable}_{year}.nc"
        filepath = output_dir / filename
        
        if not filepath.exists():
            print(f"Creating sample {variable} data...")
            
            if variable == 'tmin':
                # Minimum temperature (°C)
                base_temp = 10 + (lat_grid - lat_grid.mean()) * -0.5
                data = np.array([base_temp + 10 * np.sin(2 * np.pi * i / 365) + 
                               np.random.normal(0, 2, base_temp.shape) 
                               for i in range(365)])
            
            elif variable == 'tmax':
                # Maximum temperature (°C)  
                base_temp = 20 + (lat_grid - lat_grid.mean()) * -0.5
                data = np.array([base_temp + 15 * np.sin(2 * np.pi * i / 365) + 
                               np.random.normal(0, 3, base_temp.shape)
                               for i in range(365)])
            
            elif variable == 'prcp':
                # Precipitation (mm/day)
                base_precip = 2.0 + (lat_grid - lat_grid.mean()) * 0.1
                seasonal = 1 + 0.5 * np.sin(2 * np.pi * np.arange(365) / 365)
                data = np.array([np.maximum(0, base_precip * seasonal[i] + 
                               np.random.exponential(1, base_precip.shape))
                               for i in range(365)])
            
            # Create xarray Dataset
            ds = xr.Dataset({
                variable: (['time', 'y', 'x'], data)
            }, coords={
                'time': dates,
                'y': lats,
                'x': lons
            })
            
            # Set attributes
            ds.attrs['title'] = f'Sample {variable.upper()} data for EEMT tutorials'
            ds[variable].attrs['units'] = '°C' if 'temp' in variable else 'mm/day'
            ds[variable].attrs['long_name'] = {
                'tmin': 'Daily minimum temperature',
                'tmax': 'Daily maximum temperature', 
                'prcp': 'Daily precipitation'
            }[variable]
            
            # Save to NetCDF
            ds.to_netcdf(filepath, format='NETCDF4', engine='netcdf4')
            print(f"✅ Created: {filepath}")
        
        climate_files[variable] = str(filepath)
    
    return climate_files


def validate_dataset(filepath: str, data_type: str = 'auto') -> Dict:
    """
    Validate downloaded dataset for quality issues
    
    Parameters:
    filepath: Path to data file
    data_type: 'elevation', 'temperature', 'precipitation', or 'auto'
    
    Returns:
    Dictionary with validation results
    """
    filepath = Path(filepath)
    
    if not filepath.exists():
        return {'valid': False, 'error': 'File does not exist'}
    
    try:
        if filepath.suffix.lower() in ['.tif', '.tiff']:
            # Raster data validation
            with rasterio.open(filepath) as src:
                data = src.read(1)
                profile = src.profile
                
                # Auto-detect data type
                if data_type == 'auto':
                    if np.nanmin(data) < -100 or np.nanmax(data) > 10000:
                        data_type = 'elevation'
                    elif np.nanmin(data) < 0 and np.nanmax(data) < 100:
                        data_type = 'temperature'
                    else:
                        data_type = 'unknown'
                
                results = {
                    'valid': True,
                    'file': str(filepath),
                    'data_type': data_type,
                    'crs': str(profile['crs']),
                    'shape': data.shape,
                    'dtype': str(profile['dtype']),
                    'nodata': profile.get('nodata'),
                    'valid_pixels': int(np.sum(~np.isnan(data))),
                    'coverage_pct': float(np.sum(~np.isnan(data)) / data.size * 100),
                    'min_value': float(np.nanmin(data)),
                    'max_value': float(np.nanmax(data)),
                    'mean_value': float(np.nanmean(data))
                }
                
                # Type-specific validation
                if data_type == 'elevation':
                    results.update({
                        'has_negative_elev': bool(np.any(data < -500)),
                        'elevation_range': float(np.nanmax(data) - np.nanmin(data)),
                        'likely_units': 'meters' if np.nanmax(data) > 100 else 'unknown'
                    })
                
                elif data_type == 'temperature':
                    results.update({
                        'realistic_range': bool(np.all((data >= -50) & (data <= 60))),
                        'temp_range': float(np.nanmax(data) - np.nanmin(data)),
                        'likely_units': 'Celsius' if np.nanmax(data) < 100 else 'unknown'
                    })
                
                elif data_type == 'precipitation':
                    results.update({
                        'no_negative': bool(np.all(data >= 0)),
                        'max_daily': float(np.nanmax(data)),
                        'likely_units': 'mm/day' if np.nanmax(data) < 1000 else 'unknown'
                    })
                
                return results
        
        elif filepath.suffix.lower() in ['.nc', '.nc4']:
            # NetCDF validation
            import xarray as xr
            
            with xr.open_dataset(filepath) as ds:
                results = {
                    'valid': True,
                    'file': str(filepath),
                    'data_type': 'netcdf',
                    'variables': list(ds.data_vars.keys()),
                    'dimensions': dict(ds.dims),
                    'coordinates': list(ds.coords.keys()),
                    'time_range': None,
                    'spatial_extent': None
                }
                
                # Check for time dimension
                if 'time' in ds.dims:
                    time_var = ds.coords['time']
                    results['time_range'] = [str(time_var.min().values), str(time_var.max().values)]
                
                # Check for spatial dimensions
                if all(dim in ds.dims for dim in ['x', 'y']) or all(dim in ds.dims for dim in ['lon', 'lat']):
                    x_dim = 'x' if 'x' in ds.dims else 'lon'
                    y_dim = 'y' if 'y' in ds.dims else 'lat'
                    
                    x_coords = ds.coords[x_dim]
                    y_coords = ds.coords[y_dim]
                    
                    results['spatial_extent'] = {
                        'west': float(x_coords.min()),
                        'east': float(x_coords.max()),
                        'south': float(y_coords.min()),
                        'north': float(y_coords.max())
                    }
                
                return results
        
        else:
            return {'valid': False, 'error': f'Unsupported file type: {filepath.suffix}'}
    
    except Exception as e:
        return {'valid': False, 'error': str(e)}


def print_validation_report(validation_result: Dict):
    """
    Print a formatted validation report
    
    Parameters:
    validation_result: Result from validate_dataset()
    """
    result = validation_result
    
    print(f"📊 Dataset Validation Report")
    print(f"{'='*50}")
    
    if not result.get('valid', False):
        print(f"❌ INVALID: {result.get('error', 'Unknown error')}")
        return
    
    print(f"✅ File: {Path(result['file']).name}")
    print(f"📁 Type: {result.get('data_type', 'unknown')}")
    
    if 'shape' in result:
        print(f"📐 Shape: {result['shape']}")
        print(f"🎯 Coverage: {result['coverage_pct']:.1f}%")
        print(f"📊 Range: {result['min_value']:.2f} to {result['max_value']:.2f}")
        
        # Type-specific information
        if result['data_type'] == 'elevation':
            print(f"🏔️  Elevation range: {result.get('elevation_range', 0):.1f} m")
            if result.get('has_negative_elev'):
                print(f"⚠️  Warning: Contains elevations below -500m")
        
        elif result['data_type'] == 'temperature':
            print(f"🌡️  Temperature range: {result.get('temp_range', 0):.1f}°")
            if not result.get('realistic_range', True):
                print(f"⚠️  Warning: Unrealistic temperature values")
        
        elif result['data_type'] == 'precipitation':
            print(f"🌧️  Max daily precipitation: {result.get('max_daily', 0):.1f} mm")
            if not result.get('no_negative', True):
                print(f"⚠️  Warning: Contains negative precipitation values")
    
    if 'variables' in result:
        print(f"📊 Variables: {', '.join(result['variables'])}")
        if result.get('time_range'):
            print(f"📅 Time range: {result['time_range'][0]} to {result['time_range'][1]}")
    
    print(f"{'='*50}")


if __name__ == "__main__":
    # Test the utilities
    print("Testing EEMT data access utilities...")
    
    # Test sample DEM creation
    dem_file = download_sample_dem()
    validation = validate_dataset(dem_file, 'elevation')
    print_validation_report(validation)
    
    # Test sample climate data
    bbox = [-110.5, 32.0, -110.0, 32.5]
    climate_files = download_sample_climate_data(bbox)
    
    for var, filepath in climate_files.items():
        print(f"\n{var.upper()} validation:")
        validation = validate_dataset(filepath)
        print_validation_report(validation)