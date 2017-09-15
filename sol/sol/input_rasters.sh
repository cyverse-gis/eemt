#!/bin/bash

set -e
set -v

INPUT_DEM=$1
DEM_GRID=`basename $INPUT_DEM | sed 's/\.tif//'`

# import DEM
saga_cmd -f=q --cores=1 io_gdal 0 -FILES $INPUT_DEM -GRIDS $DEM_GRID

# Run Slope, Aspect, Curvature
saga_cmd -f=q --cores=1 ta_morphometry 0 -ELEVATION $DEM_GRID.sgrd -SLOPE slope_grid_dec -ASPECT aspect_grid_dec -UNIT_SLOPE=1 -UNIT_ASPECT=1

# Export Files as GeoTiffs
saga_cmd -f=q --cores=1 io_gdal 2 -GRIDS slope_grid_dec.sgrd -FILE slope_dec.tif
saga_cmd -f=q --cores=1 io_gdal 2 -GRIDS aspect_grid_dec.sgrd -FILE aspect_dec.tif


