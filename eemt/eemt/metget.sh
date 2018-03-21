#!/bin/bash

set -e

URL=$1
ULX=$2
ULY=$3
LRX=$4
LRY=$5
OUT_DEM=$6

DEM=`basename $URL`
wget -nv -O $DEM $URL

OUT_DIR=`dirname $OUT_DEM`
mkdir -p $OUT_DIR

#Need buffers of 2km around the width and height of the Met file to make sure the entire DEM is overlapped by Met tiles

gdal_translate -projwin $ULX $ULY $LRX $LRY -of GTiff $DEM $OUT_DEM

rm -f $DEM
