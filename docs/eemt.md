# Input & Equations

## :material-terrain: Topographic Input Data

### :material-elevation-rise: Digital Elevation Models

Digital Elevation Models (DEM) are available from a variety of public data repositories in cloud-native file format, i.e., cloud optimized geotiff (COG), or as cloud native collections, i.e., Google Earth Engine (GEE).

[:material-terrain: OpenTopography](https://opentopography.org){target=_blank}

[:simple-nasa: NASA Data](https://www.earthdata.nasa.gov/learn/find-data){target=_blank}

[:simple-googleearth: GEE Collections](https://developers.google.com/earth-engine/datasets/tags/dem){target=_blank}

[:simple-microsoft: Microsoft Planetary Computer STAC](https://planetarycomputer.microsoft.com/catalog#DEMs){target=_blank}

#### Matching the Coordinate Reference Systems of both the DEMs and Climatology data

A critical component of developing a spatial interpolation the climate data involves reprojecting the DEM to the climate observations. Because there is only one DEM, and potentially thousands of climate layers we will warp the coordinate reference system (CRS) of the DEM to match the DAYMET data.

Our BASH scripting uses the `gdalwarp` command to change the DEM CRS to the same projection system as DAYMET. 

Any .TIF file with projection data can be converted to the DAYMET projection using this script.

The DAYMET projection is: "Lambert Conformal Conic, in the WGS_84 datum, with 1st standard parallel at 25 degrees N, 2nd standard parallel at 60 degrees N (latitude of origin 42.5 degrees); and a central meridian of -100 degrees W."

If using DEMs from OpenTopo, they will likely will be in different projections and datums depending on the various projects they originated from. 

To determine the projection, we suggest using `gdalinfo`

```{bash}
gdalinfo dem.tif
```

Warp projection to DAYMET:

```{bash}
gdalwarp -overwrite -s_srs EPSG:26911 -t_srs "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs" -tr 10 10 -r bilinear -multi -dstnodata 0 -of GTiff dem.tif dem_llc.tif
```

### Slope Aspect

Slope and Aspect are calculated from the DEM using [GRASS `r.slope.aspect`](https://grass.osgeo.org/grass82/manuals/r.slope.aspect.html){target=_blank}

```{bash}
r.slope.aspect elevation=dem.tif slope=slope aspect=aspect
```

### Topographic Wetness Index

Topographic Wetness Index ($TWI_i$) ([Beven and Kirkby 1979](https://doi.org/10.1080/02626667909491834){target=_blank}) is computed for each pixel as

$$ TWI_i = ln( \frac{a_i}{tan{\beta_i}}) $$

where $a_i$ is the upslope contributing area in square meters ($m^2$) and $\beta_i$ is the local slope. 

$a_i$ = contributing area in meters square [$m^{2$], calculated using using the D-Infinity multiple flow direction approach as described by [Tarboton (1997)]( https://doi.org/10.1029/96WR03137){target=_blank}

$tan{\beta_i}$ = the tangent of the slope (in degree units)

The contributing area was calculated using [`r.topoidx`](https://grass.osgeo.org/grass82/manuals/r.topidx.html){target=_blank} .

A normalized wetness index $\alpha_i$ is computed as

$$ \alpha_i = \frac{TWI_i}{\Sigma_{i=1}^N{TWI_i}} $$

where $N$ is number of pixels in contributing or study area. The normalization ensures conservation of mass of the effective precipitation term for a given catchment.

### :material-image-filter-black-white: Surface Albedo & Reflectance

Albedo and reflectance use existing data products. 

## :material-weather-sunny: Insolation

To calculate the solar irradiation we used open source GRASS-GIS `r.sun` in two different modes: (i) topographical influence (slope aspect with shading), and  (ii) flat surface. Both modes were required to create a unitless index for upscaling the local surface temperature

The radiation term was calculated using the LiDAR-derive digital elevation model (DEM) bare-earth model with two different modes using `r.sun`.  

$$ S_i = {S_{topo}} / {S_{flat}} $$

where $S_{topo}$ is direct shortwave radiation of the topographic surface calculated based on area latitude and topography 

$S_{flat}$ is the direct radiation for a free flat surface where constant values of zero are used for slope and aspect. $S_{flat}$ is the assumed normal temperature of a flat surface with no local shading from topographic features.

Both solar radiation datasets were calculated at an hourly time step, and summated to monthly.

## :material-weather-sunny: Net Radiation

Net radiation ($R_n$) was calculated for each month in mega joules ($MJ  m^2  {month^{-1}}$) as

$$R_n = S_{topo} (1 - a) + L_n \quad (W m^{-2}) $$ 

where $S_{topo}$ is , $a$ is albedo over the study area extracted from the [MODIS MCD43A3 data product](https://lpdaac.usgs.gov/products/mcd43a3v061/){target=_blank}, $L_n$ is the net longwave radiation. 

[Durcik and Rasmussen](/docs/assets/EEMT_topo_description.pdf){target=_blank} calculated $L_n$ based on air temperature following [Allen et al. (1998)](https://www.scscourt.org/complexcivil/105cv049053/volume3/172618e_5xagwax8.pdf){target=_blank} as

$$ L_n = \alpha {T_i}^4 (0.34−0.14 \sqrt{e_a})(1.35 \frac{R_s}{R_{so}} - 0.35) \quad (W m^{-2}) $$

where $\alpha$ is Stefan-Boltzmann constant ($4.903 \ 10^{-9} MJ \ K^{-4} m^{-2} d^{-1}$), $Ti$ is locally modified temperature ($C^{\circ}$), $e_a$ (VP) is actual vapor pressure ($kPa$), $R_s$ is solar radiation and $R_{so}$ is clear-sky solar radiation ($W m^{-2}$). In computation, we assumed that $R_s = R_{so}$

??? Tip "Converting Energy Units"

    Radiation can be expressed in terms of instantaneous Watts per meter square ($W m^{-2}$) or as Mega Joules per day ($MJ d^{-1}$). Joules are used to represent Watt energy over time:

    $$1 \frac{W}{m^2} = 1 \frac{J}{m^2} s $$

    To convert divide by time

    $$ d^{-1} = 60 (seconds) * 60 (min) *24 (hours) = 86400 s $$

```{bash}
r.sun -s elevin=DEM aspin=aspect slopein=slope day="1" step="0.05" dist="1" insol_time=hours_sun glob_rad=total_sun 
```

where

 `-s` is the shadowing effect of terrain turned on
 `aspin` is aspect input
 `slopein` is slope input
 `day` is the Julian day of the year (1-365)
 `step` is the time step, 0.05 is equal to ~3 minutes, 0.25 is 15 minutes, and 0.5 is 30 minutes.
 `insoltime` = the hours per day of sunlight [hours day-1]
 `globrad` = global radiation per day [Wh m2 day-1]

The watt-hour is not a standard unit in any formal system, but it is commonly used in electrical applications. An energy expenditure of 1Wh represents 3600 joules (3.600 x 10^3 J). To obtain joules when watt-hours are known, multiply by 3.600 x 10^3. To obtain watt-hours when joules are known, multiply by 2.778 x 10-4

```{bash}
#Local Solar Insolation
echo "Calculating local Solar Insolation in Megajoules [MJ]"
r.mapcalc "total_sun_MJ = total_sun*0.0036"
```

where

`total_sun_MJ` = output converted into megajoules per month
`total_sun` = average global radiation per day [Wh m2 day-1]

1 Wh = 3600 J

Joules to Megajoules: 3600 J / 1,000,000 J = 0.0036 

The `rmean.sh` can calculate the sum, average, median, standard deviation, and variance in solar radiation across the entire month.

The daily average global radiation [MJ day-1] is what we use to calculate Penman-Monteith PET.

Correcting local temperature variation based on the aspect of exposure is done by estimating the ratio of obvserved solar radiation versus that of a flat surface. Angles that are pointed toward the sun have greater radiation, and thus a higher air temperature

Because we must calculate a ratio of solar radiation we are going to run r.sun twice. Once using a zeros raster for both slope and aspect without terrain shadows, and once using the actual slope and aspect with terrain shadowing effects turned on.
To create a zeros raster you can use r.mapcalc and write a conditional statement for the DEM. 

The output will be a raster called zeros where if there is an elevation value greater than zero it gets a zero value, else it is null.

Now, rerun r.sun with the zeros raster set as the slope and aspect:

```{bash}
#Calculate Slope and Aspect
echo "Running r.slope.aspect"
r.slope.aspect elevation=dem slope=slope_dec aspect=aspect_dec
#Create flat map
echo "Creating Flat Map"
r.mapcalc "zeros=if(dem>0,0,null())"
echo "Running r.sun on Flat Map"
#Using dem and flat slope and aspect, generate a global insolation model with local shading off
r.sun elevin=dem aspin=zeros slopein=zeros day=$DAY step=$STEPSIZE dist=$INTERVAL glob_rad=flat_total_sun

#Using dem and slope and aspect (decimal degrees), generate a global insolation model with local shading effects on
echo "Running r.sun using dem, aspect, slope"
r.sun -s elevin=dem aspin=aspect_dec slopein=slope_dec day=$DAY step=$STEPSIZE dist=$INTERVAL insol_time=hours_sun glob_rad=total_sun
```

where

`flat_total_sun` = the total solar radiation calculated for any pixel with 0 slope and 0 aspect and no shading effect

The final mapcalc calculation will multiply the ratio of total sun to flat surface: 

```{bash}
r.mapcalc S_i=total_sun/flat_total_sun
r.mapcalc tmin_topo=tmin_loc
r.mapcalc tmax_topo=tmax_loc+(S_i-(1/S_i))
```

where

`S_i` = is a ratio of total shortwave radiation on the observed surface versus shortwave radiation of the flat surface

The `tmin_topo` is the same for `tmin_loc` because minimum temperatures are met at night in the absence of solar influences. 

### :material-pine-tree: Normalized Difference Vegetation Index (NDVI)

The ubiquitous Normalized Difference Vegegation Index (NDVI) ([Tucker 1979](https://doi.org/10.1016/0034-4257(79)90013-0){target=_blank}) is calculated:

$$NDVI = \frac{(NIR - Red)}{(NIR + Red)}$$

where, NIR is near-infrared band (0.85 - 0.88 µm) and Red is the red band (0.64 - 0.67 µm)

### :material-leaf: Leaf Area Index (LAI)

Leaf Area Index (LAI) was derived using a vegetation index approach relating LAI and remotely sensed NDVI. 

A 1-m resolution NAIP 4-band imagery dataset (red, blue, green, and near infrared spectra) was used as the base data for calculating LAI. 

NDVI was calculated from the NAIP near infrared (NIR) and red bands ([Huete et al. 1994](https://doi.org/10.1016/0034-4257(94)90018-3){target=_blank}): 

[GEE LAI datasets](https://developers.google.com/earth-engine/datasets/tags/lai){target=_blank}

[GEE Landsat LAI algorithm](https://github.com/yanghuikang/Landsat-LAI){target=_blank}

[Microsoft Planetary Computer LAI datasets](https://planetarycomputer.microsoft.com/dataset/modis-15A3H-061){target=_blank}

## :material-weather-partly-rainy: Climatic Input Data

EEMT requires the climatic history from point locations (weather stations) as spatial interpolation over topographic space.

Gridded climate products include the PRISM Gorup at Oregon State University, and the DAYMET climate product from the Oak Ridge National Lab (ORNL) Distributed Active Archive Center (DAAC).

Temperature data are presented from both minimum and maximum diurnal temperatures and average (mean) monthly temperature.

### PRISM

[PRISM Climate Group](https://prism.oregonstate.edu/){target=_blank} data are available from 1980-2020.

PRISM are avaiable at 800m resolution for a $ fee, or 4KM for free.

### DAYMET

[DAYMET v4.3](https://daymet.ornl.gov/){target=_blank} are 1KM resolution. These data were recently rereleased as [Cloud Optimized GeoTiff](https://cogeo.org){target=_blank}.

??? info "Downloading DAYMET data for local caching"
    I downloaded the latest COG `.tif` DAYMET v4 format using a `wget` script:

    ```bash
    wget --verbose --no-parent --random-wait -r -nd --user=<username> ---password=<password> --accept tif --reject html,nc https://daac.ornl.gov/daacdata/daymet/Daymet_V4_Monthly_Climatology/data
    ```

    There are ~ 240 GiB of `.tif` COG format data for the DAYMET v4. These data rehosted on the CyVerse Data Store for faster access to compute on the CyVerse Discovery Environment data workbench.

DAYMET layer parameters:

`tmax` = Temperature Maximum
`tmin` = Temperature Minimum
`srad` = Solar Radiation
`vp` = Vapor Pressure
`swe` = Snow Water Equivalent
`prcp` = Precipitation
`dayl` = Day Length
`na_dem` = national digital elevation model (DEM)

# Calculations for EEMT

## :material-weather-snowy-rainy: Monthly Precipitation

Precipitation ($PPT$) data are calculated daily and summated on a monthly time scale.

Units of precipitation $PPT$ are centimeters ($cm$) per month $_{cm/M}$

## :fontawesome-solid-temperature-high: Local Temperature correction 

Correcting temperature for local conditions

```{bash}
#Locally Corrected Temperature
echo "Calculating locally corrected Temperature"
r.mapcalc "tmin_loc = tmin-0.00649*(dem-dem_1km)"
r.mapcalc "tmax_loc = tmax-0.00649*(dem-dem_1km)"
```

where:

`tmin` = temperature minimum by month from DAYMET. Units are $^\circ C$, resolution is $1 km^2$. 

`tmax` = temperature max by month from DAYMET.

`0.00649` is equal to the environmental lapse rate of a stationary atmosphere set at 6.49°C per 1,000 m elevation above sea level (rather than two adiabatic lapse rates: dry = 9.8°C and moist = 5.0°C).

`dem` = high resolution DEM

`dem1km` = the DAYMET DEM model [$1 km^2$].

`tmin_loc` = output file Units are $C^\circ$ resolution is defined by DAYMET base DEM. 

`tmax_loc` = same as for `tmin_loc`

The input and output files should be in units °C with a typical range of values between -10 °C and 45 °C for most of North America

Alternatively, we can use the DAYMET 1km product directly - as it has already undergone an elevation-lapse rate atmospheric correction for temperature. 

If we choose this method we need to first smooth the pixelation which is apparent between 1km pixels such that there are no hard edges in our data. 

To do this we use a bicubic smoothing spline. 

We also add a 4km buffer (4 pixel edge) to the tile to make sure the edge effect of the interpolation does not adversely impact the values of our reference DEM surface area.

```{bash}
#Interpolating DAYMET Data to match the DEM: https://grass.osgeo.org/grass64/manuals/r.resamp.interp.html
echo "Interpolating DAYMET Data, increasing region size to include a 4km buffer around DEM"
g.region rast=dem_input -p
#Adds a 4km buffer around the bounding region to make sure enough DAYMET pixels are included for a 16-cell bicubic interpolation over the DEM
g.region n=n+4000 e=e+4000 w=w-4000 s=s-4000 -p
echo "Interpolating TMIN to scale of DEM"
r.resamp.interp tmin output=tmin_int meth=bicubic
echo "Interpolating TMAX to scale of DEM"
r.resamp.interp tmax output=tmax_int meth=bicubic
echo "Interpolating PRCP to scale of DEM"
r.resamp.interp prcp output=prcp_int meth=bicubic
echo "Interpolating VP to scale of DEM"
r.resamp.interp vp output=vp_int meth=bicubic

```

## Local Potential Evaporation-Transpiration (PET) using Hamon's Equation

Estimating PET from local conditions

$$ PET_H = \frac{2.1 H^2 e_s }{T_i 273.2 } \quad (m s^{-1})  $$

where $H$ is daylight hours for a given month and latitude, $T_i$ is the mean locally modified temperature, and $e_s$ in kilo Pascals [kPa] is saturated vapor pressure calculated as the mean of the local minimum and maximum saturated vapor pressure (Allen et al., 1998):

$$ e_s = \frac{e_s(T_{max}) + e_s(T_{min})}{2} \quad (kPa) $$

where $e_s$ is the saturated vapor pressure at Tmax and Tmin calculated as: 

$$ e_s = 0.6108 e^{\frac{12.27T}{T237.3} } \quad (kPa) $$

where $T$ is $T_{max}$ or $T_{min}$ ($C^{\circ}$). 

```{bash}
# Local Potential Evapotranspiration for EEMT-Trad
# See Rasmussen et al. 2015 Supplemental 1: https://dl.sciencesocieties.org/publications/vzj/abstracts/0/0/vzj2014.07.0102
# Also see http://www.saecanet.com/20100716/saecanet_calculation_page.php?pagenumber=556
# and http://nest.su.se/mnode/Methods/penman.htm
echo "Calculating local Potential Evaporation-Transpiration (PET) for EEMT-Trad using Hamon's Equation"
r.mapcalc "es_tmin_loc = 0.6108*exp((17.27*tmin_loc)/(tmin_loc+237.3))"
r.mapcalc "es_tmax_loc = 0.6108*exp((17.27*tmax_loc)/(tmax_loc+237.3))"
r.mapcalc "e_s = (es_tmax_loc+es_tmin_loc)/2"
r.mapcalc "tmean_loc = (tmax_loc+tmin_loc)/2" 
r.mapcalc "PET_Trad = (29.8*hours_sun*e_s)/(tmean_loc+273.2)"
```

where:

`es_tmin_loc` and `es_tmax_loc` are the min and max locally adjusted vapor pressure [kPa].
`e_s` is the mean saturated vapor pressure es [kPa].
`hours_sun` is the average day length during the month, calculated from the `rmean.sh` - using the average day length.
`PET_Trad` must be in units of mm day-1.

## Local PET using Penman-Monteith

Potential evaporation from a pan was used in calculating $EEMT_{topo}$ using the Penman-Montieth equation (Shuttleworth, 1993): 

$$ PET_{PM} = \frac{\Delta (R_n - G) + \rho_a c_p \frac{VP_d}{r_a}  }{\lambda (\Delta + \gamma (1+ \frac{r_s}{r_a}))} \quad (m s^{-1}) $$

Where,

$PET_{PM}$ = Evapotranspiration [mm day-1];

$R_n$ = net radiation at the crop surface [MJ m-2 d-1];

$G$ = soil heat flux density [MJ m-2 d-1];

$T$ = mean daily air temperature at 2 m height [°C];

$u^2$ = wind speed at 2 m height [m s-1];

$e_s$ = saturation vapor pressure [kPa];

$e_a$ = actual vapor pressure [kPa];

$\delta_e$ = $e_s - e_a$ = saturation vapor pressure deficit [kPa];

$\Delta$ = slope of the vapor pressure curve, [kPa ºC-1];

$\gamma$ = psychrometric constant, [kPa °C-1];

$L$ = latent heat of vaporization, 2.26 [MJ kg−1];

$M = molecular weight of water vapor in dry air, 0.622

$P_a$ = air density [kg m-3];

$C_p$ = specific heat of moist air [MJ kg-1 *C-1];

$R_a$ = [s m-1]



Potential evapotranspiration was computed using the [Penman-Montieth](http://www.agraria.unirc.it/documentazione/materiale_didattico/1462_2016_412_24509.pdf) equation from [Shuttleworth 1991](https://doi.org/10.1007/978-1-4612-3032-8_5){target=_blank}) and simplified for calculating potential evapotranspiration from a pan surface such that the surface resistance term (rs) in the denominator is assumed equal to zero

$$ PET_{PM} = \frac{\Delta (R_n - G) + \rho_a c_p \frac{VP_d}{r_a}  }{\lambda (\Delta + \gamma)} \quad (m s^{-1}) $$

where the first term in the numerator is the radiation balance with net radiation $R_n$ and ground heat flux is $G$. The second term in the numerator is the ventilation term that includes vapor pressure deficit $VP_d$ and aerodynamic resistance $r_a$ computed as 

$$ r_a = \frac{ 4.72 ( ln\frac{z_m}{z_o})^2 }{1+0.536 U_z} \quad (kPa)$$

where $z_m$ is the height of meteorological measurements at 2 m above ground level, $z_o$ is the aerodynamic roughness of an open water surface set equal to $0.00137 m$ following [Thom and Oliver (1977)](https://doi.org/10.1002/qj.49710343610){target=_blank}, and $U_z$ is wind speed. The remaining terms include the slope of the saturated vapor pressure-temperature relationship $\Delta$ calculated using mean air temperature as

$$ \Delta = 0.04145 e^{0.06088T} $$

the psychrometric constant γ determined as

$$ \gamma = c_p P / \epsilon \lambda $$

where $c_p$ is specific heat of moist air at constant pressure $1.013 10^{-3} MJ kg^{-1} \degree C-^{1} $, $\epsilon$ is the ratio of molar mass of water to that of dry air, $P$ is atmospheric pressure computed from measured values at the base station using elevation $z$ locally estimated lapse rate $\nu$ determined as

$$ P = 101.3 (\frac{293 - \nu z}{ 293})^5.26 $$

mean air density ρa , and λ the latent heat of evaporation of water.

Actual evapotranspiration $AET$ was estimated using a Budyko curve (Budyko, 1974) describing the partitioning of potential and actual evapotranspiration relative to the aridity index (ratio of annual PET to annual rainfall). Potential evapotranspiration $PET_{PM}$ and precipitation $PPT$ were converted to monthly values of $AET$ using a Zhang– Budyko curve as (Zhang et al., 2001)

$$ AET = PPT \begin{cases} 1 + \frac{ PET_{PM} }{ PPT } - [1 + \frac{PET_PM}{PPT}^w ]^{-1/w}\end{cases}$$

## :material-water-opacity: Mean saturated vapor pressure

Vapor pressure data are calculated on daily to monthly time scale.

Local monthly saturated vapor pressure $VP_s$ in Pascals ($Pa$) is computed as

$$ VP_s = 611.2 e^\frac{17.67 T_i}{T_i+243.5} \quad (kPa) $$

where $e$ is Euler's number ($2.71828$) and $T_i$ is temperature of air in degrees $C^\circ$ actual local vapor pressure is computed as

$$ VP_a = RH \frac{VP_s}{100} \quad (kPa) $$

### Vapor Pressure Deficit

local monthly vapor pressure deficit $VP_d$ is computed as

$$ VP_d = VP_s - VP_a = (100 - RH) \frac{VP_s}{100} \quad (kPa) $$

where relative humidity $RH$ is measured by the reference station and $T_i$ is local temperature.


## :material-weather-snowy-rainy: Effective Precipitation ($P_e$)

## :material-leaf: Net Primary Productivity

# Calculations for Topographic correction of EEMT

## Temperature correction using solar irradiation and shading versus a flat surface

