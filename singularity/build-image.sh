#!/bin/bash

# testing new  build

TS=`date +'%Y%m%d'`
BASENAME="eemt-v$TS"

rm -f $BASENAME.img
singularity build $BASENAME.img Singularity

