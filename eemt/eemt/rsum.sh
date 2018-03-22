#!/bin/bash

#Read options
ARGS=`getopt -o D: --long directory: -n 'rsum.sh' -- "$@"`

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
        *) echo "Internal Error"; exit 1 ;;
    esac
done
MONTH=$1; shift
WORKING_DIR=$RANDOM 
LOCATION=${DIRECTORY}/sol_data/tmp_${WORKING_DIR}/PERMANENT
GRASSRC=${DIRECTORY}/.grassrc_${WORKING_DIR}

export GISRC=${GRASSRC}


###############################################################################
#OPTIONS PARSED =>  START SETUP
###############################################################################

#Create output structure
#if [ ! -e ./global ]; then
    mkdir -p global/daily
    mkdir -p global/monthly
    mkdir -p global/annual
#fi
#if [ ! -e ./insol ]; then
    mkdir -p insol/daily
    mkdir -p insol/monthly
    mkdir -p insol/annual
#fi


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

###############################################################################
#SETUP COMPLETE => START GRASS OPERATIONS
###############################################################################

echo "Computing Series for $MONTH"
#Create new projection info
g.proj -c georef=$1

#Import Dems
g.mremove -f "*"
echo "IMPORTING"
#Need to grab and import every tif
while (( "$#" )); do
    #echo $1 > temp
    #NAME=`cut -d'.' -f2 temp`
    #echo $NAME > temp
    #NAME=`cut -d'/' -f5 temp`
    NAME=`echo $1 | sed 's;.*/;;' | sed 's;\..*;;'`

    echo "IMPORTING UNDER NAME: $NAME for Argument $1"

    r.in.gdal input=$1 output=$NAME
    shift
done
rm -f temp

g.region -s rast=$NAME

#compute Sum
echo "Calculating sum for global/monthly/total_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='total_sun_day_*' separator=,`" output=total_sun_${MONTH}_sum method=sum
echo "Calculating sum for insol/monthly/hours_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='hours_sun_day_*' separator=,`" output=hours_sun_${MONTH}_sum method=sum
echo "Calculating sum for global/monthly/flat_total_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='flat_total_sun_day_*' separator=,`" output=flat_total_sun_${MONTH}_sum method=sum

# Compute average 
echo "Calculating average for global/monthly/total_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='total_sun_day_*' sep=,`" output=total_sun_${MONTH}_average method=average
echo "Calculating average for insol/monthly/hours_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='hours_sun_day_*' sep=,`" output=hours_sun_${MONTH}_average method=average
echo "Calculating average for global/monthly/flat_total_sun_${MONTH}_sum.tif"
r.series -n input="`g.list rast pattern='flat_total_sun_day_*' sep=,`" output=flat_total_sun_${MONTH}_average method=average

# Compute median
# r.series -n input="`g.list pattern='total_sun_day_*' sep=,`" output=total_sun_${MONTH}_median method=median
# r.series -n input="`g.list pattern='hours_sun_day_*' sep=,`" output=hours_sun_${MONTH}_median method=median

# Compute standard deviation
# r.series -n input="`g.list pattern='total_sun_day_*' sep=,`" output=total_sun_${MONTH}_stddev method=stddev
# r.series -n input="`g.list pattern='hours_sun_day_*' sep=,`" output=hours_sun_${MONTH}_stddev method=stddev

# Compute variance
# r.series -n input="`g.list pattern='total_sun_day_*' sep=,`" output=total_sun_${MONTH}_variance method=variance
# r.series -n input="`g.list pattern='hours_sun_day_*' sep=,`" output=hours_sun_${MONTH}_variance method=variance

# Sum Maps
echo "Printing out Sum maps: global/monthly/total_sun_${MONTH}_sum.tif"
r.out.gdal -c input=total_sun_${MONTH}_sum output=${DIRECTORY}/global/monthly/total_sun_${MONTH}_sum.tif
echo "Printing out Sum maps: global/monthly/hours_sun_${MONTH}_sum.tif"
r.out.gdal -c input=hours_sun_${MONTH}_sum output=${DIRECTORY}/insol/monthly/hours_sun_${MONTH}_sum.tif
echo "Printing out Sum maps: global/monthly/flat_total_sun_${MONTH}_sum.tif"
r.out.gdal -c input=flat_total_sun_${MONTH}_sum output=${DIRECTORY}/global/monthly/flat_total_sun_${MONTH}_sum.tif

# Average Maps
echo "Printing out Average maps: global/monthly/total_sun_${MONTH}_average.tif"
r.out.gdal -c input=total_sun_${MONTH}_average output=${DIRECTORY}/global/monthly/total_sun_${MONTH}_average.tif
echo "Printing out Average maps: global/monthly/hours_sun_${MONTH}_average.tif"
r.out.gdal -c input=hours_sun_${MONTH}_average output=${DIRECTORY}/insol/monthly/hours_sun_${MONTH}_average.tif
echo "Printing out Average maps: global/monthly/flat_total_sun_${MONTH}_average.tif"
r.out.gdal -c input=flat_total_sun_${MONTH}_average output=${DIRECTORY}/global/monthly/flat_total_sun_${MONTH}_average.tif

# Median Maps
# r.out.gdal -c input=total_sun_${MONTH}_median output=${DIRECTORY}/global/monthly/total_sun_${MONTH}_median.tif
# r.out.gdal -c input=hours_sun_${MONTH}_median output=${DIRECTORY}/insol/monthly/hours_sun_${MONTH}_median.tif

# Standard Deviation Maps
# r.out.gdal -c input=total_sun_${MONTH}_stddev output=${DIRECTORY}/global/monthly/total_sun_${MONTH}_stddev.tif
# r.out.gdal -c input=hours_sun_${MONTH}_stddev output=${DIRECTORY}/insol/monthly/hours_sun_${MONTH}_stddev.tif

# Variance Maps
# r.out.gdal -c input=total_sun_${MONTH}_variance output=${DIRECTORY}/global/monthly/total_sun_${MONTH}_variance.tif
# r.out.gdal -c input=hours_sun_${MONTH}_variance output=${DIRECTORY}/insol/monthly/hours_sun_${MONTH}_variance.tif

###############################################################################
#GRASS OPERATIONS COMPLETE => CLEAN UP FILES
###############################################################################
rm -rf ${DIRECTORY}/sol_data/tmp_${WORKING_DIR}/
rm $GRASSRC
