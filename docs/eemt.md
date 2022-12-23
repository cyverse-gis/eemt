# Input & Equations

## :material-terrain: Topographic Input Data

### :material-elevation-rise: Digital Elevation Models

Digital Elevation Models (DEM) are available from a variety of public data repositories in cloud-native file format, i.e., cloud optimized geotiff (COG), or as cloud native collections, i.e., Google Earth Engine (GEE).

[:material-terrain: OpenTopography](https://opentopography.org){target=_blank}

[:simple-nasa: NASA Data](https://www.earthdata.nasa.gov/learn/find-data){target=_blank}

[:simple-googleearth: GEE Collections](https://developers.google.com/earth-engine/datasets/tags/dem){target=_blank}

[:simple-microsoft: Microsoft Planetary Computer STAC](https://planetarycomputer.microsoft.com/catalog#DEMs){target=_blank}

### :material-image-filter-black-white: Surface Albedo & Reflectance

Albedo and reflectance are calculated using XXXX

## :material-weather-sunny: Insolation

To calculate the solar irradiation we used open source GRASS-GIS `r.sun` in two different modes: (i) topographical influence (slope aspect with shading), and  (ii) flat surface. Both modes were required to create a unitless index for upscaling the local surface temperature

The radiation term was calculated using the LiDAR-derive digital elevation model (DEM) bare-earth model with two different modes using `r.sun`.  

$$ S_i = {S_{topo}} / {S_{flat}} $$

where $S_{topo}$ is direct shortwave radiation of the topographic surface calculated based on area latitude and topography 

$S_{flat}$ is the direct radiation for a free flat surface where constant values of zero are used for slope and aspect. $S_{flat}$ is the assumed normal temperature of a flat surface with no local shading from topographic features.

Both solar radiation datasets were calculated at an hourly time step, and summated to monthly.

## :material-weather-sunny: Net Radiation

Net radiation ($R_n$) was calculated for each month in mega joules ($MJ  m^2  {month^{-1}}$) as

$$R_n = S_{topo} (1 - a) + L_n$$

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

## :material-water-opacity: Mean saturated vapor pressure


Vapor pressure data are calculated on daily to monthly time scale.

## :material-weather-snowy-rainy: Effective Precipitation ($P_e$)

## :material-leaf: Net Primary Productivity

# Calculations for Topographic correction of EEMT

## Temperature correction using solar irradiation/shading / flat surface


