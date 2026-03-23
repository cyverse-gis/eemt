#!/bin/bash

set -e

# rsun_prep.sh - One-time slope/aspect precomputation for the solar workflow
#
# This script creates pre-computed slope and aspect rasters from a DEM,
# eliminating the need to recalculate r.slope.aspect in each of the 365
# daily r.sun tasks. At 0.5m resolution (51.4M cells), this saves ~30-60
# seconds per daily task, or 3-6 hours over a full annual run.
#
# Usage: rsun_prep.sh <dem.tif> -D <directory>
# Outputs: slope_dec.tif, aspect_dec.tif (in working directory)

# Read options
ARGS=`getopt -o D: --long directory: -n 'rsun_prep.sh' -- "$@"`
if [ $? -ne 0 ]; then
    echo "Incorrect usage"
    exit 1
fi

eval set -- "$ARGS"
while true; do
  case "$1" in
    -D|--directory)
      shift
      if [ -n "$1" ]; then
        DIRECTORY=$1
        shift;
      fi
    ;;
    --)
      shift
      break
      ;;
    *)
      echo "Argument Error: $1"
      echo
      exit 1
      ;;
  esac
done

# Input files
DEM=$1

# Set Working Directory
WORKING_DIR=$RANDOM
LOCATION=${DIRECTORY}/sol_data/tmp_prep_${WORKING_DIR}/PERMANENT
GRASSRC=${DIRECTORY}/.grassrc_prep_${WORKING_DIR}
export GISRC=${GRASSRC}
export GRASS_VERBOSE=0

###############################################################################
# OPTIONS PARSED => START SETUP
###############################################################################

echo
echo "Pre-computing slope and aspect from DEM: $DEM"

# Create location directory structure
if [ ! -e $LOCATION ]; then
    mkdir -p $LOCATION
fi

# Set wind info
if [ ! -e ${LOCATION}/DEFAULT_WIND ]; then
cat > "${LOCATION}/DEFAULT_WIND" << __EOF__
proj: 99
zone: 0
north: 1
south: 0
east: 1
west: 0
cols: 1
rows: 1
e-w resol: 1
n-s resol: 1
top: 1.000000000000000
bottom: 0.000000000000000
cols3: 1
rows3: 1
depths: 1
e-w resol3: 1
n-s resol3: 1
t-b resol: 1
__EOF__
cp ${LOCATION}/DEFAULT_WIND ${LOCATION}/WIND
fi

# Set GRASS settings
echo "GISDBASE: ${DIRECTORY}/sol_data" > $GRASSRC
echo "LOCATION_NAME: tmp_prep_${WORKING_DIR}" >> $GRASSRC
echo "MAPSET: PERMANENT" >> $GRASSRC
echo "GRASS_GUI: text" >> $GRASSRC

###############################################################################
# SETUP COMPLETE => START GRASS OPERATIONS
###############################################################################

# Create new projection info
g.proj -c georef=$DEM

# Import DEM
echo "Importing DEM"
r.in.gdal input=$DEM output=dem

# Set GRASS Region
echo "Setting Region"
g.region -sa raster=dem

# Generate slope and aspect (decimal degrees)
echo "Computing slope and aspect (decimal degrees) with GRASS r.slope.aspect"
r.slope.aspect elevation=dem slope=slope_dec aspect=aspect_dec

# Export as GeoTiff with LZW compression
echo "Exporting slope_dec.tif"
r.out.gdal createopt="COMPRESS=LZW" -c input=slope_dec output=./slope_dec.tif
echo "Exporting aspect_dec.tif"
r.out.gdal createopt="COMPRESS=LZW" -c input=aspect_dec output=./aspect_dec.tif

echo "Slope and aspect precomputation complete"

###############################################################################
# GRASS OPERATIONS COMPLETE => CLEAN UP FILES
###############################################################################
rm -rf ${DIRECTORY}/sol_data/tmp_prep_${WORKING_DIR}/
rm $GRASSRC
