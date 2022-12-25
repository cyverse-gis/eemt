# Input & Equations

## :material-terrain: Topographic Input Data

### :material-elevation-rise: Digital Elevation Models

Digital Elevation Models (DEM) are available from a variety of public data repositories in cloud-native file format, i.e., cloud optimized geotiff (COG), or as cloud native collections, i.e., Google Earth Engine (GEE).

[:material-terrain: OpenTopography](https://opentopography.org){target=_blank}

[:simple-nasa: NASA Data](https://www.earthdata.nasa.gov/learn/find-data){target=_blank}

[:simple-googleearth: GEE Collections](https://developers.google.com/earth-engine/datasets/tags/dem){target=_blank}

[:simple-microsoft: Microsoft Planetary Computer STAC](https://planetarycomputer.microsoft.com/catalog#DEMs){target=_blank}

#### Slope Aspect

Slope and Aspect are calculated from the DEM using [GRASS `r.slope.aspect`](https://grass.osgeo.org/grass82/manuals/r.slope.aspect.html){target=_blank}

#### Topographic Wetness Index

Topographic Wetness Index ($TWI_i$) ([Beven and Kirkby 1979](https://doi.org/10.1080/02626667909491834){target=_blank}) is computed for each pixel as

$$ TWI_i = ln( \frac{a_i}{tan{\beta_i}}) $$

where $a_i$ is the upslope contributing area in square meters ($m^2$) and $\beta_i$ is the local slope. The contributing area was calculated using [`r.topoidx`](https://grass.osgeo.org/grass82/manuals/r.topidx.html){target=_blank} using the D-Infinity multiple flow direction approach as described by [Tarboton (1997)]( https://doi.org/10.1029/96WR03137){target=_blank}.

A normalized wetness index $\alpha_i$ is computed as

$$ \alpha_i = \frac{TWI_i}{\Sigma_{i=1}^N{TWI_i}} $$

where $N$ is number of pixels in catchment or study area. The normalization ensures conservation of mass of the effective precipitation term for a given catchment or area.

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

# Calculations for EEMT

## :material-weather-snowy-rainy: Monthly Precipitation

Precipitation ($PPT$) data are calculated daily and summated on a monthly time scale.

Units of precipitation $PPT$ are centimeters ($cm$) per month $_{cm/M}$

## :fontawesome-solid-temperature-high: Local Temperature correction 

Correcting temperature for local conditions

## Local Potential Evaporation-Transpiration (PET) using Hamon's Equation

Estimating PET from local conditions

$$ PET_H = \frac{2.1 H^2 e_s }{T_i 273.2 } \quad (m s^{-1})  $$

where $H$ is daylight hours for a given month and latitude, $T_i$ is the mean locally modified temperature, and $e_s$ in kilo Pascals [kPa] is saturated vapor pressure calculated as the mean of the local minimum and maximum saturated vapor pressure (Allen et al., 1998):

$$ e_s = \frac{e_s(T_{max}) + e_s(T_{min})}{2} \quad (kPa) $$

where $e_s$ is the saturated vapor pressure at Tmax and Tmin calculated as: 

$$ e_s = 0.6108 e^{\frac{12.27T}{T237.3} } \quad (kPa) $$

where $T$ is $T_{max}$ or $T_{min}$ ($C^{\circ}$). 

## Local PET using Penman-Monteith

Potential evaporation from a pan was used in calculating $EEMT_{topo}$ using the Penman-Montieth equation (Shuttleworth, 1993): 

$$ PET_{PM} = \frac{\Delta (R_n - G) + \rho_a c_p \frac{VP_d}{r_a}  }{\lambda (\Delta + \gamma (1+ \frac{r_s}{r_a}))} \quad (m s^{-1}) $$

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

## Temperature correction using solar irradiation/shading / flat surface

