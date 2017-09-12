#!/bin/bash

TS=`date +'%Y%m%d'`
BASENAME="eemt-v$TS"

rm -f $BASENAME.img
singularity create --size 8192 $BASENAME.img
singularity bootstrap $BASENAME.img Singularity
