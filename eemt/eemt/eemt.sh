#!/bin/bash

set -e

# Input Files
DIRECTORY=$1
MONTH=$2
YEAR=$3
DEM=$4
NA_DEM=$5
TMIN=$6
TMAX=$7
VP=$8
PRCP=$9
TWI=${10}
TOTAL_SUN=${11}
HOURS_SUN=${12}
FLAT_SUN=${13}
SLOPE_RAD=${14}
ASPECT_RAD=${15}


echo "================================================================================"
echo "Proj_dir: $DIRECTORY"
echo "Month: $MONTH"
echo "Year: $YEAR"
echo "DEM: $DEM"
echo "NA_DEM: $NA_DEM"
echo "TMin: $TMIN"
echo "Tmax: $TMAX"
echo "Vp: $VP"
echo "PRCP: $PRCP"
echo "TWI: $TWI"
echo "Total_Sun: $TOTAL_SUN"
echo "Hours_Sun: $HOURS_SUN"
echo "Flat_Sun: $FLAT_SUN"
echo "Slope: $SLOPE_RAD"
echo "Aspect: $ASPECT_RAD"
echo "================================================================================"

# Expand directory
DIRECTORY=`cd $DIRECTORY && pwd`

WORKING_DIR=$RANDOM 
LOCATION=${DIRECTORY}/sol_data/tmp_${WORKING_DIR}/PERMANENT
GRASSRC=${DIRECTORY}/.grassrc_${WORKING_DIR}

export GISRC=${GRASSRC}

export GRASS_VERBOSE=0

###############################################################################
# START GRASS SETUP
###############################################################################
# Create location directory structure
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


# Set GRASS settings
echo "GISDBASE: ${DIRECTORY}/sol_data" > $GRASSRC
echo "LOCATION_NAME: tmp_${WORKING_DIR}" >> $GRASSRC
echo "MAPSET: PERMANENT" >> $GRASSRC
echo "GRASS_GUI: text" >> $GRASSRC

###############################################################################
# SETUP COMPLETE => START GRASS OPERATIONS
###############################################################################

# Create new projection info
g.proj -c georef=$DEM
#Remove any extraneous files
g.mremove -f "*"

# Import DEM
echo "Importing local DEM"
r.in.gdal input=${DEM} output=dem_10m

# Set Region
echo "Setting Region"
g.region -s rast=dem_10m

# Import DAYMET Data - tmin,tmax,twi,prcp,vp
echo "Importing DAYMET Data:"
echo "Importing DAYMET TMIN"
r.in.gdal input=${TMIN} output=tmin
echo "Importing DAYMET TMAX"
r.in.gdal input=${TMAX} output=tmax
echo "Importing DAYMET TWI"
r.in.gdal input=${TWI} output=twi
echo "Importing DAYMET PRCP"
r.in.gdal input=${PRCP} output=prcp
echo "Importing DAYMET VP"
r.in.gdal input=${VP} output=vp

# Import r.sun results
echo "Importing total Solar radiation"
r.in.gdal input=${TOTAL_SUN} output=total_sun
echo "Importing daily hours of sun"
r.in.gdal input=${HOURS_SUN} output=hours_sun
echo "Importing Slope (radians)"
r.in.gdal input=${SLOPE_RAD} output=slope_rad
echo "Importing Aspect (radians)"
r.in.gdal input=${ASPECT_RAD} output=aspect_rad

# Import Daymet reference 1 km DEM
echo "Importing DAYMET 1km DEM reference elevation model"
r.in.gdal input=${NA_DEM} output=dem_1km

# Import the flat surface solar map
echo "Importing monthly sum of flat surface solar radiation"
r.in.gdal input=${FLAT_SUN} output=flat_total_sun

# Locally Corrected Temperature
echo "Calculating locally corrected Temperature based on environmental lapse rate of international standard at 6.49C/km elevation above sea level"
r.mapcalc "tmin_loc = tmin-0.00649*(dem_10m-dem_1km)"
r.mapcalc "tmax_loc = tmax-0.00649*(dem_10m-dem_1km)"

# Local Potential Evapotranspiration for EEMT-Trad
# See Rasmussen et al. 2015 Supplemental 1: https://dl.sciencesocieties.org/publications/vzj/abstracts/0/0/vzj2014.07.0102
# Also see http://www.saecanet.com/20100716/saecanet_calculation_page.php?pagenumber=556
# and http://nest.su.se/mnode/Methods/penman.htm
echo "Calculating local Potential Evaporation-Transpiration (PET) for EEMT-Trad using Hamon's Equation"
r.mapcalc "tmean_loc = (tmax_loc+tmin_loc)/2"
r.mapcalc "es_tmin_loc = if(tmin_loc > 0, 0.6108*exp((17.27*tmin_loc)/(tmin_loc+237.3)), 0)"
r.mapcalc "es_tmax_loc = if(tmax_loc > 0, 0.6108*exp((17.27*tmax_loc)/(tmax_loc+237.3)), 0)"
r.mapcalc "e_s = if(tmean_loc > 0, (es_tmax_loc+es_tmin_loc)/2, 0)"
r.mapcalc "PET_Trad = if(e_s > 0, (29.8*hours_sun*e_s)/(tmean_loc+273.2), 0)"

# Locally Corrected Temperature (modified by global solar radiation)
echo "Calculating locally corrected min and max temperature (maximum temp modified by solar angle, min temp assumed at night)"
r.mapcalc "S_i = total_sun/flat_total_sun"
r.mapcalc "tmin_topo = tmin_loc"
r.mapcalc "tmax_topo = tmax_loc+(S_i-(1/S_i))"
r.mapcalc "tmean_topo = (tmax_topo+tmin_topo)/2"

# Potential Evapotranspiration for EEMT-Topo using Penman-Monteith 
echo "Calculating Potential Evapotranspiration (PET) for EEMT-Topo using the Penman-Monteith Equation"
echo "Calculating psychromatic constant g"
r.mapcalc "g_psy = 1013*(101.3*((293-0.00649*dem_10m)/293)^5.26)"
echo "Calculating slope of the saturaved vapor pressure-temperature relationship"
r.mapcalc "m_vp = 0.04145*exp(0.06088*tmean_topo)"
echo "Calculating aerodynamic resistance"
r.mapcalc "ra = (4.72*(log(2/0.00137))*2)/(1+0.536*5)"
echo "Calculating local vapor pressure"
r.mapcalc "vp_loc = 6.11*(10^(7.5*tmin_topo)/(237.3+tmin_topo))"
echo "Calculating average temperature corrected vapor saturation"
r.mapcalc "f_tmin_topo = if(tmin_topo > 0, 6.108*exp((17.27*tmin_topo)/(tmin_topo+237.3)), 0)"
r.mapcalc "f_tmax_topo = if(tmax_topo > 0, 6.108*exp((17.27*tmin_topo)/(tmin_topo+237.3)), 0)"
r.mapcalc "vp_s_topo = if(tmean_topo > 0, (f_tmax_topo+f_tmin_topo)/2, 0)"
echo "Calculating mean air density"
r.mapcalc "p_a = 101325*exp(-9.80665*0.289644*dem_10m/(8.31447*288.15))/(287.35*tmean_topo*273.125)"
echo "Calculating solar influenced PET"
echo "Calculating local radiant energy in joules"
r.mapcalc "total_sun_joules = total_sun*3600"
r.mapcalc "PET_topo = if(tmean_topo > 0, (m_vp*total_sun_joules+p_a*1013*((vp_s_topo-vp_loc)/ra))/(2450000*(m_vp+g_psy)), 0)"

echo "Calculating topographic redistribution of precipitation on water budget"
# Local Water Balance (accounting for topographic redistribution of run-off)
echo "Calculating Median of TWI for local water balance"
r.mapcalc "twi_median=median(twi)"
echo "Calculating median conservative wetness index"
r.mapcalc "a_i = twi/twi_median"
echo "Calculating Actual ET using a Zhang-Budyko curve"
r.mapcalc "AET_zb = if(tmean_topo > 0, prcp*(1+(PET_topo/prcp)-(1+(PET_topo/prcp)^2.63)^(1/2.63)), 0)"
echo "Calculating the fraction of monthly precipitation at each pixel"
r.mapcalc "P_eff = prcp - AET_zb"
r.mapcalc "F = if(prcp > 0, a_i*P_eff, 0)"

# EEMT-Traditional
echo "Calculating the Effective Precipitation term E_ppt for EEMT-Trad"
r.mapcalc "E_ppt_trad = if(prcp > 0, (prcp - (PET_Trad*10))*4185.5, 0)" #PET_Trad was in units of cm/month - converted to mm
echo "Calculating E_bio term for Net Primary Productivity for EEMT-Trad"
r.mapcalc "NPP_trad = if(tmean_loc > 0,3000*(1+exp(1.315-0.119*(tmax_loc+tmin_loc)/2)^-1), 0)"
r.mapcalc "E_bio_trad = if(tmean_loc > 0, NPP_trad*(22*10^6), 0)"
echo "Calculating EEMT-Trad = E_ppt + E_bio"
r.mapcalc "EEMT_Trad = (E_ppt_trad + E_bio_trad)/1000000"

# EEMT-Topographical
echo "Calculating parameters for EEMT-Topo"
echo "Calculating northness"
r.mapcalc "N = cos(slope_rad)*sin(aspect_rad)"
echo "Calculating Net Primary Productivity modified by topography, NPP_topo, based on Whittaker and Niering 1975"
r.mapcalc "NPP_topo = 0.39*dem_10m+346*N-187"
echo "Calculating energy from NPP, E_bio_topo"
r.mapcalc "E_bio_topo = NPP_topo*(22*10^6)"
echo "Calculating effective energy from precipitation, E_ppt_topo"

# At this point everything is still in Joules [J] - convert back to Mega Joules [MJ] 
r.mapcalc "E_ppt_topo = if(prcp > 0, F*4185.5*tmean_topo*E_bio_topo, 0)"
echo "Calculating EEMT_topo"
r.mapcalc "EEMT_Topo = (E_ppt_topo + E_bio_topo)/1000000"

mkdir -p ${DIRECTORY}/eemt
r.out.gdal -c createopt="BIGTIFF=IF_SAFER,COMPRESS=LZW" input=EEMT_Topo output=${DIRECTORY}/eemt/EEMT_Topo_${MONTH}_${YEAR}.tif
r.out.gdal -c createopt="BIGTIFF=IF_SAFER,COMPRESS=LZW" input=EEMT_Trad output=${DIRECTORY}/eemt/EEMT_Trad_${MONTH}_${YEAR}.tif

rm -rf ${DIRECTORY}/sol_data
