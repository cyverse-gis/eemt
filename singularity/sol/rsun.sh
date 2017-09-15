#!/bin/bash

set -e

#Read options
ARGS=`getopt -o d:D: --long day:,directory: -n 'rsun.sh' -- "$@"`
if [ $? -ne 0 ]; then
echo "Incorrect usage"
exit 1
fi
eval set -- "$ARGS"
while true; do
case "$1" in
-d|--day)
shift;
if [ -n "$1" ]; then
DAY=$1
shift
fi
;;
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
*) echo "Internal Error"; exit 1 ;;
esac
done

#Input files
DEM=$1
SLOPE=$2
ASPECT=$3
#Set Working Directory
WORKING_DIR=$RANDOM
LOCATION=${DIRECTORY}/sol_data/tmp_${WORKING_DIR}/PERMANENT
GRASSRC=${DIRECTORY}/.grassrc_${WORKING_DIR}
export GISRC=${GRASSRC}

export GRASS_VERBOSE=0

###############################################################################
#OPTIONS PARSED => START SETUP
###############################################################################

echo
echo "Calculating for day $DAY"

#Create output structure
if [ ! -e ./global ]; then
mkdir -p global/daily
mkdir -p global/monthly
mkdir -p global/annual
fi
if [ ! -e ./insol ]; then
mkdir -p insol/daily
mkdir -p insol/monthly
mkdir -p insol/annual
fi
#Create location directory structure
if [ ! -e $LOCATION ]; then
mkdir -p $LOCATION
fi
#Set wind info
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
#Set GRASS settings
echo "GISDBASE: ${DIRECTORY}/sol_data" > $GRASSRC
echo "LOCATION_NAME: tmp_${WORKING_DIR}" >> $GRASSRC
echo "MAPSET: PERMANENT" >> $GRASSRC
echo "GRASS_GUI: text" >> $GRASSRC
#Test STEPSIZE set at 30 minutes (0.5) - final run needs to be set to 15 minutes (0.25)
STEPSIZE=0.5
###############################################################################
#SETUP COMPLETE => START GRASS OPERATIONS
###############################################################################
if [ -e /unsupported/czo/czorc ]; then
    source /unsupported/czo/czorc
fi

echo "Running r.sun for day $DAY"
echo "DEM: $DEM"
#Create new projection info
g.proj -c georef=$DEM
#Import Dem
#g.remove -f "*"
echo "Importing DEM"
r.in.gdal input=$DEM output=dem
echo "Importing Slope (decimal degrees)"
r.in.gdal input=$SLOPE output=slope_dec
echo "Importing Aspect (decimal degrees)"
r.in.gdal input=$ASPECT output=aspect_dec

#Set Region
echo "Setting Region"
g.region -sa rast=dem
#Using dem and slope and aspect (decimal degrees), generate a global insolation model with local shading effects (-s) on
#All other settings are default
echo "Running r.sun for global radiation and hours insolation time with step size $STEPSIZE"
r.sun elevation=dem aspect=aspect_dec slope=slope_dec day=$DAY step=$STEPSIZE insol_time=hours_sun glob_rad=total_sun
echo "Day # $DAY done!"
#Output
echo "Export Global Radiation"
r.out.gdal createopt="COMPRESS=LZW" -c input=total_sun output=./global/daily/total_sun_day_${DAY}.tif
echo "Export Hours Sun"
r.out.gdal createopt="COMPRESS=LZW" -c input=hours_sun output=./insol/daily/hours_sun_day_${DAY}.tif

###############################################################################
#GRASS OPERATIONS COMPLETE => CLEAN UP FILES
###############################################################################
rm -rf ${DIRECTORY}/sol_data/tmp_${WORKING_DIR}/
rm $GRASSRC

