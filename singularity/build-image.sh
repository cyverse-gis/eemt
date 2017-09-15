#!/bin/bash

# testing new  build

TS=`date +'%Y%m%d'`
BASENAME="eemt-v$TS"

rm -f $BASENAME.img
singularity create --size 4000 $BASENAME.img
singularity bootstrap $BASENAME.img Singularity

