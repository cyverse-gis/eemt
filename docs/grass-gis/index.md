---
title: GRASS GIS
---

# GRASS GIS for EEMT Calculations

## Overview

GRASS GIS provides the core geospatial analysis capabilities for EEMT calculations, particularly the r.sun module for solar radiation modeling. This guide covers installation, configuration, and parallel processing techniques.

## Contents

1. Installation and Setup
2. r.sun Solar Radiation Modeling  
3. Parallel Processing with r.sun.mp
4. Terrain Analysis
5. Batch Processing Workflows
6. Performance Optimization

## Installation and Setup

### GRASS GIS Installation

#### Ubuntu/Debian
```bash
# Install GRASS GIS 8.x
sudo apt update
sudo apt install software-properties-common
sudo add-apt-repository ppa:ubuntugis/ubuntugis-unstable
sudo apt update
sudo apt install grass grass-dev grass-doc

# Verify installation
grass --version
```

#### macOS
```bash
# Via Homebrew
brew install grass

# Or download from: https://grass.osgeo.org/download/mac/
```

#### Windows
```bash
# Download OSGeo4W installer
# https://trac.osgeo.org/osgeo4w/

# Or use conda
conda install -c conda-forge grass
```

### Creating a GRASS Location

#### From DEM File
```bash
# Create location from DEM projection
grass -c /path/to/your_dem.tif ~/grassdata/eemt_project/PERMANENT

# Alternative: create location interactively  
grass ~/grassdata/eemt_project/PERMANENT
```

#### Verify Setup
```bash
# Check projection information
g.proj -p

# Set computational region to match DEM
g.region raster=your_dem -p

# Display basic info
r.info your_dem
```

## r.sun Solar Radiation Modeling

### Basic r.sun Usage

```bash
# Import DEM
r.in.gdal input=dem.tif output=elevation

# Calculate slope and aspect  
r.slope.aspect elevation=elevation slope=slope_deg aspect=aspect_deg

# Basic solar radiation calculation
r.sun elevation=elevation aspect=aspect_deg slope=slope_deg \
      day=180 glob_rad=solar_june29 insol_time=hours_june29

# View results
d.rast solar_june29
```

### Advanced r.sun Parameters

#### Temporal Settings
```bash
# Single day calculation
r.sun elevation=dem day=180 step=0.25 \
      glob_rad=global_rad insol_time=sunshine_hours

# Multi-day calculation
r.sun elevation=dem start_day=170 end_day=190 day_step=1 \
      step=0.25 glob_rad=summer_radiation
```

#### Atmospheric Parameters
```bash
# Atmospheric conditions
r.sun elevation=dem day=180 \
      linke_value=3.0 \        # Atmospheric turbidity (1.0-8.0)
      albedo_value=0.2 \       # Surface albedo (0.0-1.0)  
      slope_value=0.1 \        # Solar constant correction
      aspect_value=180.0 \     # Default south-facing slope
      glob_rad=solar_output insol_time=sun_hours
```

#### Horizon and Shading
```bash
# Include horizon effects  
r.sun elevation=dem day=180 \
      horizonstep=30 \         # Horizon calculation step (degrees)
      horizon=horizon_angles \  # Output horizon file
      glob_rad=solar_with_horizon

# Cast shadows from features
r.sun elevation=dem day=180 \
      cast_shadow=shadow_map \  # Shadow raster output
      glob_rad=solar_with_shadows
```

## Parallel Processing with r.sun.mp

### OpenMP Multi-core Processing

```bash
# Set number of threads
export OMP_NUM_THREADS=8

# Run r.sun with multiple threads
r.sun.mp elevation=dem aspect=aspect_deg slope=slope_deg \
         day=180 step=0.25 threads=8 \
         glob_rad=solar_parallel insol_time=hours_parallel
```

### Python Wrapper for Parallel Processing

Based on the analysis of `/sol/rsun.sh`, here's the enhanced parallel processing approach:

```python
#!/usr/bin/env python3
"""
Enhanced r.sun parallel processing for EEMT calculations
Based on sol/run-workflow with modern improvements
"""

import os
import sys
import argparse
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor, as_completed
import subprocess
import tempfile
import shutil
from pathlib import Path

class GrassSolarCalculator:
    """GRASS GIS solar radiation calculator with parallel processing"""
    
    def __init__(self, dem_path, output_dir, num_threads=None):
        self.dem_path = Path(dem_path)
        self.output_dir = Path(output_dir)
        self.num_threads = num_threads or mp.cpu_count()
        
        # Create output directories
        self.output_dir.mkdir(parents=True, exist_ok=True)
        (self.output_dir / 'global' / 'daily').mkdir(parents=True, exist_ok=True)
        (self.output_dir / 'insol' / 'daily').mkdir(parents=True, exist_ok=True)
        
    def setup_grass_environment(self, day):
        """Create temporary GRASS environment for single day calculation"""
        
        # Create temporary directory
        temp_dir = tempfile.mkdtemp(prefix=f'grass_day_{day}_')
        location_dir = Path(temp_dir) / 'grassdata' / f'solar_day_{day}' / 'PERMANENT'
        location_dir.mkdir(parents=True, exist_ok=True)
        
        # GRASS environment variables
        grass_env = os.environ.copy()
        grass_env.update({
            'GISDBASE': str(location_dir.parent.parent),
            'LOCATION_NAME': f'solar_day_{day}',
            'MAPSET': 'PERMANENT',
            'GRASS_GUI': 'text',
            'GRASS_VERBOSE': '0'
        })
        
        return temp_dir, grass_env
    
    def calculate_daily_solar(self, day, step=0.25, linke_value=3.0, albedo_value=0.2):
        """Calculate solar radiation for a single day"""
        
        temp_dir, grass_env = self.setup_grass_environment(day)
        
        try:
            # Start GRASS session
            grass_cmd = [
                'grass', '--text',
                f"{grass_env['GISDBASE']}/{grass_env['LOCATION_NAME']}/{grass_env['MAPSET']}"
            ]
            
            # GRASS commands
            commands = f"""
# Create location from DEM
g.proj -c georef={self.dem_path}

# Import DEM
r.in.gdal input={self.dem_path} output=dem

# Set region
g.region raster=dem

# Calculate slope and aspect  
r.slope.aspect elevation=dem slope=slope_deg aspect=aspect_deg

# Run r.sun.mp with optimal threading
r.sun.mp elevation=dem aspect=aspect_deg slope=slope_deg \\
         day={day} step={step} \\
         linke_value={linke_value} albedo_value={albedo_value} \\
         threads={min(self.num_threads, 4)} \\
         glob_rad=solar_global insol_time=solar_hours

# Export results
r.out.gdal input=solar_global output={self.output_dir}/global/daily/total_sun_day_{day}.tif \\
           createopt="COMPRESS=LZW,TILED=YES"
           
r.out.gdal input=solar_hours output={self.output_dir}/insol/daily/hours_sun_day_{day}.tif \\
           createopt="COMPRESS=LZW,TILED=YES"
"""
            
            # Execute GRASS commands
            process = subprocess.Popen(
                grass_cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=grass_env
            )
            
            stdout, stderr = process.communicate(input=commands)
            
            if process.returncode != 0:
                raise RuntimeError(f"GRASS error for day {day}: {stderr}")
                
            print(f"Completed day {day}")
            return day
            
        finally:
            # Cleanup temporary directory
            shutil.rmtree(temp_dir, ignore_errors=True)
    
    def calculate_annual_solar(self, year_days=None, step=0.25, linke_value=3.0, albedo_value=0.2):
        """Calculate solar radiation for multiple days in parallel"""
        
        if year_days is None:
            year_days = range(1, 366)  # Full year
        
        print(f"Calculating solar radiation for {len(year_days)} days using {self.num_threads} threads")
        
        # Process days in parallel
        with ProcessPoolExecutor(max_workers=self.num_threads) as executor:
            
            # Submit all tasks
            future_to_day = {
                executor.submit(
                    self.calculate_daily_solar, 
                    day, step, linke_value, albedo_value
                ): day for day in year_days
            }
            
            # Collect results
            completed_days = []
            for future in as_completed(future_to_day):
                day = future_to_day[future]
                try:
                    result = future.result()
                    completed_days.append(result)
                    print(f"✓ Day {day} completed ({len(completed_days)}/{len(year_days)})")
                except Exception as e:
                    print(f"✗ Day {day} failed: {e}")
        
        return completed_days
    
    def calculate_monthly_summaries(self):
        """Calculate monthly summaries from daily outputs"""
        
        months = {
            'jan': range(1, 32),   'feb': range(32, 60),   'mar': range(60, 91),
            'apr': range(91, 121), 'may': range(121, 152), 'jun': range(152, 182),
            'jul': range(182, 213), 'aug': range(213, 244), 'sep': range(244, 274),
            'oct': range(274, 305), 'nov': range(305, 335), 'dec': range(335, 366)
        }
        
        for month, days in months.items():
            
            # Build list of daily files
            global_files = [f"{self.output_dir}/global/daily/total_sun_day_{day}.tif" 
                          for day in days]
            insol_files = [f"{self.output_dir}/insol/daily/hours_sun_day_{day}.tif" 
                         for day in days]
            
            # Check if all daily files exist
            missing_files = [f for f in global_files + insol_files if not os.path.exists(f)]
            if missing_files:
                print(f"Warning: Missing files for {month}: {len(missing_files)} files")
                continue
            
            # Calculate monthly sums using GDAL
            global_output = f"{self.output_dir}/global/monthly/total_sun_{month}_sum.tif"
            insol_output = f"{self.output_dir}/insol/monthly/hours_sun_{month}_sum.tif"
            
            # Sum global radiation
            global_vrt = f"/tmp/global_{month}.vrt"
            subprocess.run([
                'gdalbuildvrt', '-separate', global_vrt
            ] + global_files, check=True)
            
            subprocess.run([
                'gdal_calc.py', '-A', global_vrt, '--calc=sum(A,axis=0)',
                '--outfile', global_output, '--co', 'COMPRESS=LZW'
            ], check=True)
            
            # Sum insolation hours  
            insol_vrt = f"/tmp/insol_{month}.vrt"
            subprocess.run([
                'gdalbuildvrt', '-separate', insol_vrt
            ] + insol_files, check=True)
            
            subprocess.run([
                'gdal_calc.py', '-A', insol_vrt, '--calc=sum(A,axis=0)', 
                '--outfile', insol_output, '--co', 'COMPRESS=LZW'
            ], check=True)
            
            print(f"✓ {month} monthly summary completed")

def main():
    parser = argparse.ArgumentParser(description='EEMT Solar Radiation Calculator')
    parser.add_argument('dem', help='Input DEM file path')
    parser.add_argument('--output', '-o', default='./solar_output', 
                       help='Output directory')
    parser.add_argument('--threads', '-t', type=int, default=mp.cpu_count(),
                       help='Number of parallel threads')
    parser.add_argument('--step', type=float, default=0.25,
                       help='Solar calculation time step (hours)')
    parser.add_argument('--linke', type=float, default=3.0,
                       help='Linke atmospheric turbidity factor')
    parser.add_argument('--albedo', type=float, default=0.2,
                       help='Surface albedo value')
    parser.add_argument('--days', nargs='+', type=int,
                       help='Specific days to calculate (default: full year)')
    
    args = parser.parse_args()
    
    # Initialize calculator
    calculator = GrassSolarCalculator(
        args.dem, 
        args.output, 
        args.threads
    )
    
    # Calculate solar radiation
    days = args.days if args.days else range(1, 366)
    completed = calculator.calculate_annual_solar(
        days, args.step, args.linke, args.albedo
    )
    
    # Calculate monthly summaries
    if len(completed) >= 300:  # Most of year calculated
        calculator.calculate_monthly_summaries()
    
    print(f"Solar radiation calculation complete!")
    print(f"Output directory: {args.output}")
    print(f"Completed days: {len(completed)}")

if __name__ == '__main__':
    main()
```

### Optimized r.sun.mp Usage

#### Memory Management
```bash
# For large DEMs, set memory limits
export GRASS_VECTOR_TMPDIR_MAPSET=/tmp
export GRASS_RASTER_TMPDIR_MAPSET=/tmp

# Increase cache size
g.gisenv set="GRASS_CACHE_SIZE=2048"
```

#### Multi-core Configuration
```bash
# Optimize for system architecture
export OMP_NUM_THREADS=$(nproc)
export GRASS_NUM_THREADS=$(nproc)

# NUMA-aware processing (large systems)
numactl --cpunodebind=0 --membind=0 r.sun.mp elevation=dem ...
```

### High-Performance r.sun Workflow

Based on the `/sol/rsun.sh` analysis, here's the optimized workflow:

```bash
#!/bin/bash
# High-performance solar radiation calculation
# Enhanced version of sol/rsun.sh

set -e

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--day)
      DAY="$2"
      shift 2
      ;;
    -s|--step)  
      STEP="$2"
      shift 2
      ;;
    -t|--threads)
      NUM_THREADS="$2"
      shift 2
      ;;
    -l|--linke)
      LINKE_VALUE="$2"
      shift 2
      ;;
    -a|--albedo)
      ALBEDO_VALUE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      DEM_FILE="$1"
      shift
      ;;
  esac
done

# Set defaults
NUM_THREADS=${NUM_THREADS:-$(nproc)}
STEP=${STEP:-0.25}
LINKE_VALUE=${LINKE_VALUE:-3.0}
ALBEDO_VALUE=${ALBEDO_VALUE:-0.2}
OUTPUT_DIR=${OUTPUT_DIR:-"./solar_output"}

# Validate inputs
if [[ ! -f "$DEM_FILE" ]]; then
    echo "Error: DEM file not found: $DEM_FILE"
    exit 1
fi

# Create temporary GRASS location
TEMP_LOCATION=$(mktemp -d)
GRASS_LOCATION="$TEMP_LOCATION/solar_calc"

# Setup GRASS environment
export GISDBASE="$TEMP_LOCATION"
export LOCATION_NAME="solar_calc"
export MAPSET="PERMANENT"
export GRASS_GUI="text"
export GRASS_VERBOSE=0

echo "Starting solar calculation for day $DAY"
echo "Threads: $NUM_THREADS, Step: ${STEP}h, Linke: $LINKE_VALUE, Albedo: $ALBEDO_VALUE"

# Create output directories
mkdir -p "$OUTPUT_DIR/global/daily"
mkdir -p "$OUTPUT_DIR/insol/daily"

# Run GRASS commands
grass --text "$GRASS_LOCATION" --exec << EOF
# Create location from DEM
g.proj -c georef=$DEM_FILE

# Import DEM
r.in.gdal input=$DEM_FILE output=dem

# Set computational region
g.region raster=dem

# Calculate terrain derivatives
echo "Calculating slope and aspect..."
r.slope.aspect elevation=dem slope=slope_deg aspect=aspect_deg

# Calculate solar radiation with optimal threading
echo "Running r.sun.mp for day $DAY..."
r.sun.mp elevation=dem aspect=aspect_deg slope=slope_deg \\
         day=$DAY step=$STEP \\
         linke_value=$LINKE_VALUE albedo_value=$ALBEDO_VALUE \\
         threads=$NUM_THREADS \\
         glob_rad=solar_global insol_time=solar_hours

# Export results with compression
echo "Exporting results..."
r.out.gdal input=solar_global \\
           output=$OUTPUT_DIR/global/daily/total_sun_day_$DAY.tif \\
           createopt="COMPRESS=LZW,TILED=YES,BLOCKXSIZE=512,BLOCKYSIZE=512"

r.out.gdal input=solar_hours \\
           output=$OUTPUT_DIR/insol/daily/hours_sun_day_$DAY.tif \\
           createopt="COMPRESS=LZW,TILED=YES,BLOCKXSIZE=512,BLOCKYSIZE=512"

echo "Day $DAY completed successfully"
EOF

# Cleanup
rm -rf "$TEMP_LOCATION"

echo "Solar calculation for day $DAY finished"
```

### Batch Processing All Days

```python
#!/usr/bin/env python3
"""
Batch process full year of solar radiation calculations
Enhanced version of sol/run-workflow
"""

import subprocess
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor
import argparse
from pathlib import Path

def run_daily_solar(day, dem_file, output_dir, step, linke, albedo, threads_per_day):
    """Run solar calculation for single day"""
    
    cmd = [
        'bash', 'enhanced_rsun.sh',
        '--day', str(day),
        '--step', str(step),
        '--linke', str(linke),
        '--albedo', str(albedo),  
        '--threads', str(threads_per_day),
        '--output', output_dir,
        dem_file
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
        if result.returncode == 0:
            return day, True, None
        else:
            return day, False, result.stderr
    except subprocess.TimeoutExpired:
        return day, False, "Timeout after 1 hour"
    except Exception as e:
        return day, False, str(e)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dem', help='Input DEM file')
    parser.add_argument('--output', '-o', default='./solar_annual', help='Output directory')
    parser.add_argument('--workers', '-w', type=int, default=mp.cpu_count()//4, 
                       help='Number of parallel day processes')
    parser.add_argument('--threads-per-day', '-t', type=int, default=4,
                       help='Threads per daily calculation')
    parser.add_argument('--step', type=float, default=0.25, help='Time step (hours)')
    parser.add_argument('--linke', type=float, default=3.0, help='Linke turbidity')  
    parser.add_argument('--albedo', type=float, default=0.2, help='Surface albedo')
    parser.add_argument('--start-day', type=int, default=1, help='Start day of year')
    parser.add_argument('--end-day', type=int, default=365, help='End day of year')
    
    args = parser.parse_args()
    
    # Create output directory
    Path(args.output).mkdir(parents=True, exist_ok=True)
    
    # Days to process
    days = range(args.start_day, args.end_day + 1)
    
    print(f"Processing {len(days)} days using {args.workers} parallel workers")
    print(f"Each day uses {args.threads_per_day} threads")
    print(f"Total system load: {args.workers * args.threads_per_day} threads")
    
    # Process days in parallel
    completed = []
    failed = []
    
    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        
        # Submit all day calculations
        future_to_day = {
            executor.submit(
                run_daily_solar,
                day, args.dem, args.output, 
                args.step, args.linke, args.albedo, args.threads_per_day
            ): day for day in days
        }
        
        # Collect results
        for future in future_to_day:
            day, success, error = future.result()
            
            if success:
                completed.append(day)
                print(f"✓ Day {day} ({len(completed)}/{len(days)})")
            else:
                failed.append((day, error))
                print(f"✗ Day {day} failed: {error}")
    
    # Summary
    print(f"\nCompleted: {len(completed)} days")
    print(f"Failed: {len(failed)} days")
    
    if failed:
        print("\nFailed days:")
        for day, error in failed:
            print(f"  Day {day}: {error}")
    
    return len(completed) > 0

if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
```

## GPU Acceleration (GRASS 8.x)

### OpenCL Setup for r.sun

```bash
# Check OpenCL availability
grass --text << EOF
r.sun.mp --help | grep -i opencl
EOF

# Enable GPU acceleration (if available)
grass --text << EOF
# Set OpenCL device
g.gisenv set="GRASS_OPENCL_DEVICE=0"

# Run r.sun with GPU acceleration  
r.sun.mp elevation=dem aspect=aspect slope=slope \\
         day=180 step=0.1 opencl=yes \\
         glob_rad=solar_gpu insol_time=hours_gpu
EOF
```

## Memory Optimization for Large DEMs

### Tiled Processing
```bash
# Split large DEM into manageable tiles
gdal_retile.py -ps 2048 2048 -overlap 128 \\
               -targetDir dem_tiles/ large_dem.tif

# Process each tile separately
for tile in dem_tiles/*.tif; do
    echo "Processing $tile..."
    python enhanced_solar_calc.py "$tile" --output "results_$(basename $tile .tif)"
done

# Merge results
gdal_merge.py -o final_solar.tif results_*/global/monthly/*.tif
```

### Chunked Processing with GRASS
```python
def process_dem_chunks(dem_path, chunk_size=2048, overlap=128):
    """Process large DEM in chunks"""
    
    import rasterio
    from rasterio.windows import Window
    
    with rasterio.open(dem_path) as src:
        height, width = src.shape
        
        # Calculate chunk coordinates
        chunks = []
        for row in range(0, height, chunk_size - overlap):
            for col in range(0, width, chunk_size - overlap):
                
                # Define window
                window = Window(
                    col, row,
                    min(chunk_size, width - col),
                    min(chunk_size, height - row)
                )
                
                chunks.append(window)
        
        print(f"Processing {len(chunks)} chunks")
        
        # Process each chunk
        for i, window in enumerate(chunks):
            
            # Extract chunk
            chunk_data = src.read(1, window=window)
            chunk_transform = src.window_transform(window)
            
            # Save chunk as temporary file
            chunk_profile = src.profile.copy()
            chunk_profile.update({
                'height': window.height,
                'width': window.width,
                'transform': chunk_transform
            })
            
            chunk_file = f'chunk_{i}.tif'
            with rasterio.open(chunk_file, 'w', **chunk_profile) as dst:
                dst.write(chunk_data, 1)
            
            # Process chunk with solar calculator
            calculator = GrassSolarCalculator(chunk_file, f'chunk_output_{i}')
            calculator.calculate_annual_solar()
            
            # Cleanup chunk file
            os.remove(chunk_file)
```

## Performance Monitoring

### Resource Usage Tracking
```python
import psutil
import time
from functools import wraps

def monitor_performance(func):
    """Decorator to monitor CPU and memory usage"""
    
    @wraps(func)
    def wrapper(*args, **kwargs):
        
        # Initial measurements
        start_time = time.time()
        process = psutil.Process()
        start_cpu = process.cpu_percent()
        start_memory = process.memory_info().rss / 1024**2  # MB
        
        try:
            # Run function
            result = func(*args, **kwargs)
            
            # Final measurements
            end_time = time.time()
            end_cpu = process.cpu_percent()
            end_memory = process.memory_info().rss / 1024**2
            
            # Print performance stats
            duration = end_time - start_time
            print(f"\nPerformance Summary:")
            print(f"  Duration: {duration:.1f} seconds")
            print(f"  CPU usage: {end_cpu:.1f}%")
            print(f"  Memory usage: {end_memory:.1f} MB")
            print(f"  Memory change: {end_memory - start_memory:+.1f} MB")
            
            return result
            
        except Exception as e:
            print(f"Error during execution: {e}")
            raise
    
    return wrapper

# Apply to solar calculations
@monitor_performance
def calculate_solar_monitored(day, dem_file, output_dir):
    """Solar calculation with performance monitoring"""
    calculator = GrassSolarCalculator(dem_file, output_dir)
    return calculator.calculate_daily_solar(day)
```

## Advanced GRASS Configuration

### Parallel Processing Environment
```bash
# ~/.bashrc configuration for GRASS parallel processing
export GRASS_NUM_THREADS=$(nproc)
export OMP_NUM_THREADS=$(nproc)
export GRASS_CACHE_SIZE=2048
export GRASS_RENDER_IMMEDIATE=FALSE
export GRASS_COMPRESS_NULLS=1

# For HPC environments
export GRASS_BATCH_JOB=TRUE
export GRASS_GUI=text
export GRASS_VERBOSE=0
```

### Cluster/HPC Integration
```bash
#!/bin/bash
#SBATCH --job-name=eemt_solar
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=24
#SBATCH --memory=64GB
#SBATCH --time=12:00:00

# Load modules
module load grass/8.3 gdal/3.6 python/3.11

# Set GRASS environment
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export GRASS_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Run solar calculations
python enhanced_solar_calc.py $DEM_FILE \\
  --threads $SLURM_CPUS_PER_TASK \\
  --output $SLURM_SUBMIT_DIR/solar_results
```

## Troubleshooting

### Common Issues

#### Memory Errors
```bash
# Reduce processing extent
g.region -s res=30  # Decrease resolution temporarily

# Use tiled processing
r.tile input=large_dem output=dem_tile prefix=chunk_ width=2048 height=2048
```

#### Projection Issues  
```bash
# Check DEM projection
gdalinfo dem.tif | grep -i "coordinate system"

# Reproject if needed
gdalwarp -t_srs EPSG:4326 input_dem.tif output_dem_wgs84.tif
```

#### r.sun Errors
```bash
# Validate slope/aspect values
r.info slope_deg
r.info aspect_deg

# Check for null values
r.null setnull="-9999" slope_deg
```

---

Next: [Complete EEMT Workflows](../workflows/index.md)