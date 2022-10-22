#!/bin/bash

set -e
set -v

INPUT_DEM=$1
DEM_GRID=`basename $INPUT_DEM | sed 's/\.tif//'`

# import DEM
saga_cmd -f=q --cores=1 io_gdal 0 -FILES $INPUT_DEM -GRIDS $DEM_GRID

# Run Slope, Aspect, Curvature
saga_cmd -f=q --cores=4 ta_morphometry 0 -ELEVATION $DEM_GRID.sgrd -SLOPE slope_grid_rad -ASPECT aspect_grid_rad
saga_cmd -f=q --cores=4 ta_morphometry 0 -ELEVATION $DEM_GRID.sgrd -SLOPE slope_grid_dec -ASPECT aspect_grid_dec -UNIT_SLOPE=1 -UNIT_ASPECT=1

# Run Catchment Area with d-infinity [-METHOD 2] http://www.saga-gis.org/saga_module_doc/2.1.4/ta_hydrology_1.html
saga_cmd -f=q --cores=4 ta_hydrology 1 -ELEVATION $DEM_GRID.sgrd -CAREA catchment_grid -METHOD 2

# Run SAGA Wetness Index http://www.saga-gis.org/saga_module_doc/2.1.3/ta_hydrology_15.html
saga_cmd -f=q --cores=4 ta_hydrology 15 -DEM $DEM_GRID.sgrd -SLOPE slope_grid_rad.sgrd -AREA catchment_grid.sgrd -TWI twi_grid

# Export Files as GeoTiffs
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS slope_grid_rad.sgrd -FILE slope_rad.tif
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS aspect_grid_rad.sgrd -FILE aspect_rad.tif
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS slope_grid_dec.sgrd -FILE slope_dec.tif
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS aspect_grid_dec.sgrd -FILE aspect_dec.tif
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS catchment_grid.sgrd -FILE catchment.tif
saga_cmd -f=q --cores=4 io_gdal 2 -GRIDS twi_grid.sgrd -FILE twi.tif
