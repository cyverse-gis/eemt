---
title: Quick Start Guide
description: Get started with EEMT calculations in under 10 minutes
---

# Quick Start Guide

## Overview

This guide will help you run your first EEMT calculation using the web interface in under 10 minutes. We'll use a sample DEM file and default parameters to demonstrate the basic workflow.

## Prerequisites

Before starting, ensure you have:

- **Docker Desktop** installed and running ([Download Docker](https://www.docker.com/products/docker-desktop/))
- **4GB of available RAM** (8GB recommended)
- **10GB of free disk space** for data and results
- **Internet connection** for downloading climate data

## Step 1: Deploy EEMT with Docker Compose

The fastest way to get started is using Docker Compose:

```bash
# Clone the repository
git clone https://github.com/cyverse-gis/eemt.git
cd eemt

# Start the EEMT web interface
docker-compose up
```

This command will:
1. Build the EEMT container with all dependencies
2. Start the web interface on port 5000
3. Enable job monitoring on the dashboard

Wait for the message: `INFO: Application startup complete`

## Step 2: Access the Web Interface

Open your web browser and navigate to:

```
http://127.0.0.1:5000
```

You should see the EEMT Web Interface homepage with a job submission form.

## Step 3: Prepare Your First DEM

For this quick start, we'll use the included sample DEM:

```bash
# The sample DEM is located at:
# sol/examples/mcn_10m.tif

# This is a 10m resolution DEM of a small watershed
# in southeastern Arizona (Marshall Gulch, Santa Catalina Mountains)
```

### DEM Requirements

Your DEM must meet these criteria:
- **Format**: GeoTIFF (.tif or .tiff)
- **Projection**: Any valid coordinate system (will be auto-detected)
- **Resolution**: 1m to 1000m (10-30m recommended for regional analysis)
- **Size**: Under 100MB for quick processing

## Step 4: Submit Your First Job

### Using the Web Interface

1. **Select Workflow Type**: Choose "Solar Radiation Only" for a quick test
2. **Upload DEM**: Click "Choose File" and select `mcn_10m.tif`
3. **Set Parameters**:
   - **Step**: 15 (minutes between calculations)
   - **Threads**: 4 (parallel processes)
   - **Linke Turbidity**: 3.0 (clear atmosphere)
   - **Albedo**: 0.2 (typical soil/vegetation)
4. **Submit**: Click "Submit Job"

### Understanding the Parameters

| Parameter | Quick Start Value | What It Does |
|-----------|------------------|--------------|
| **Step** | 15 minutes | Time interval for solar calculations. Lower = more accurate but slower |
| **Threads** | 4 | Number of parallel processes. Match your CPU cores |
| **Linke Turbidity** | 3.0 | Atmospheric clarity. 1-2 = very clear, 3-4 = average, 5-8 = hazy |
| **Albedo** | 0.2 | Surface reflectance. 0.1 = dark soil, 0.2 = vegetation, 0.8 = snow |

## Step 5: Monitor Job Progress

After submission, you'll be redirected to the monitoring page:

```
http://127.0.0.1:5000/monitor
```

### What You'll See

```
Job ID: SOL_20240115_143022
Status: Running
Progress: Processing day 42 of 365...
Estimated Time Remaining: 8 minutes
```

### Processing Stages

1. **Initialization** (30 seconds)
   - Setting up GRASS GIS environment
   - Importing DEM
   - Calculating horizons

2. **Daily Calculations** (5-15 minutes)
   - 365 solar radiation maps
   - One calculation per day of year
   - Progress updated in real-time

3. **Aggregation** (1 minute)
   - Monthly summaries
   - Annual totals
   - Statistics generation

## Step 6: View and Download Results

When complete, the monitoring page will show:

```
Status: Completed
Processing Time: 12 minutes 34 seconds
Results: Available for download
```

### Output Files

Click "Download Results" to get a ZIP file containing:

```
results_SOL_20240115_143022.zip
├── global/
│   ├── daily/           # 365 daily solar radiation maps
│   │   ├── total_sun_day_001.tif
│   │   ├── total_sun_day_002.tif
│   │   └── ...
│   ├── monthly/         # 12 monthly summaries
│   │   ├── total_sun_01_sum.tif
│   │   ├── total_sun_02_sum.tif
│   │   └── ...
│   └── annual/          # Annual total
│       └── total_sun_annual.tif
├── metadata/
│   ├── parameters.json  # Input parameters
│   └── statistics.csv   # Summary statistics
└── logs/
    ├── workflow.log     # Processing log
    └── errors.log       # Any errors (should be empty)
```

## Step 7: Visualize Results

### Quick Visualization with QGIS

1. Open QGIS
2. Drag `total_sun_annual.tif` into the map window
3. Right-click layer → Properties → Symbology
4. Choose "Singleband pseudocolor" with "Spectral" color ramp
5. Click Apply

### Understanding the Output

Solar radiation values are in **Wh/m²** (watt-hours per square meter):

| Annual Total | Environment Type |
|--------------|------------------|
| < 1,000,000 | Deep valleys, north-facing cliffs |
| 1,000,000 - 1,500,000 | Shaded slopes, forest |
| 1,500,000 - 2,000,000 | Open terrain, grassland |
| > 2,000,000 | South-facing slopes, ridgetops |

## Next Steps

### Run a Full EEMT Analysis

Now try the complete EEMT workflow with climate data:

```bash
# From the web interface, select "Full EEMT"
# This will:
# 1. Calculate solar radiation
# 2. Download DAYMET climate data
# 3. Compute NPP and effective precipitation
# 4. Generate EEMT maps
```

### Customize Parameters

Experiment with different settings:

```python
# High-resolution analysis (slower, more accurate)
step = 5        # 5-minute intervals
threads = 8     # Use more cores

# Different environments
linke = 1.5     # Very clear mountain air
albedo = 0.8    # Snow-covered terrain

# Arid region
linke = 4.0     # Dusty atmosphere
albedo = 0.35   # Desert soil
```

### Process Your Own Study Area

1. **Prepare your DEM**:
   ```bash
   # Reproject if needed
   gdalwarp -t_srs EPSG:4326 your_dem.tif dem_wgs84.tif
   
   # Clip to study area
   gdalwarp -te xmin ymin xmax ymax dem_wgs84.tif study_area.tif
   ```

2. **Submit through web interface** with parameters appropriate for your region

3. **Monitor and download** results when complete

## Common Issues and Solutions

### Issue: Docker not starting

```bash
# Check Docker status
docker --version
docker ps

# Restart Docker Desktop
# On Mac/Windows: Use the Docker Desktop app
# On Linux:
sudo systemctl restart docker
```

### Issue: Port 5000 already in use

```bash
# Use a different port
docker-compose run -p 5001:5000 eemt-web
# Then access at http://127.0.0.1:5001
```

### Issue: Slow processing

**Solutions**:
- Increase step size (15 → 30 minutes)
- Reduce DEM resolution
- Allocate more threads
- Ensure adequate RAM available

### Issue: Climate data download fails

**Solutions**:
- Check internet connection
- Verify study area is within DAYMET coverage (North America)
- Try again (ORNL server may be temporarily unavailable)

## Tips for Best Results

### DEM Preparation

✅ **DO**:
- Use projected coordinate systems (e.g., UTM)
- Include buffer area around study region
- Fill sinks/pits in DEM before processing
- Use consistent resolution (10-30m recommended)

❌ **DON'T**:
- Use geographic coordinates for large areas
- Include ocean or large water bodies
- Mix different resolution DEMs
- Use DEMs with many NoData gaps

### Parameter Selection

**For Different Regions**:

| Region Type | Step | Linke | Albedo | Notes |
|------------|------|-------|--------|-------|
| **Mountains** | 10 | 2.0 | 0.15 | High resolution for complex terrain |
| **Desert** | 15 | 4.0 | 0.35 | Account for dust and bright soil |
| **Forest** | 15 | 3.0 | 0.15 | Dark canopy, moderate atmosphere |
| **Agricultural** | 15 | 3.5 | 0.20 | Seasonal variation important |
| **Arctic** | 30 | 1.5 | 0.80 | Very clear air, snow cover |

### Performance Optimization

```python
# For large areas (>10,000 km²)
# Split into tiles and process separately

# Tile your DEM
gdal_retile.py -ps 5000 5000 -overlap 100 large_dem.tif -targetDir tiles/

# Process each tile
for tile in tiles/*.tif:
    submit_eemt_job(tile)
    
# Merge results
gdal_merge.py -o final_eemt.tif results/*/eemt.tif
```

## Example: Complete 5-Minute Workflow

Here's a complete workflow you can run in 5 minutes with the sample data:

```bash
# 1. Start EEMT (if not already running)
cd eemt
docker-compose up -d

# 2. Wait for startup (30 seconds)
sleep 30

# 3. Submit job via curl (alternative to web interface)
curl -X POST http://127.0.0.1:5000/api/submit-job \
  -F "workflow_type=sol" \
  -F "dem_file=@sol/examples/mcn_10m.tif" \
  -F "step=30" \
  -F "num_threads=4" \
  -F "linke_value=3.0" \
  -F "albedo_value=0.2"

# 4. Monitor progress
# Job will complete in ~3 minutes with step=30

# 5. Results will be available at:
# http://127.0.0.1:5000/results/[JOB_ID]/
```

## Getting Help

### Resources

- **Documentation**: http://127.0.0.1:8000 (when running with `--profile docs`)
- **GitHub Issues**: https://github.com/cyverse-gis/eemt/issues
- **Algorithm Details**: See [Solar Radiation Algorithms](../algorithms/solar-radiation.md)
- **API Reference**: See [Web Interface API](../web-interface/api-reference.md)

### Support Channels

- **Scientific Questions**: Review [EEMT Publications](../about/publications.md)
- **Technical Issues**: Check [Development Guide](../development/index.md)
- **Bug Reports**: Use GitHub issue tracker

## Summary

You've successfully:
- ✅ Deployed EEMT using Docker
- ✅ Submitted your first job via web interface
- ✅ Monitored job progress
- ✅ Downloaded and understood results
- ✅ Learned key parameters and optimization tips

**Next**: Try the [Data Preparation Guide](data-preparation.md) to work with your own study area, or explore [Full EEMT Calculations](../algorithms/eemt-calculations.md) for complete energy balance modeling.

---

*Estimated time to complete this guide: 5-10 minutes*