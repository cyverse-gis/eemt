As a proof of concept we developed a distributed computing workflow using open-source GIS tools (GDAL, SAGA, GRASS, and QGIS) and [Makeflow]() to calculate traditional and topographically controlled "Effective Energy and Mass Transfer (EEMT)" ([Rasmussen et al. 2015](https://dl.sciencesocieties.org/publications/vzj/pdfs/0/0/vzj2014.07.0102)), which is a measure of the available free energy for physical and chemical work [units in mega joules per meter square over time: MJ m2 yr-1], at the surface of the critical zone.

To calculate EEMT we use a digital elevation model (DEM) and monthly averaged precipitation, vapor pressure, and temperature series. With open-source GIS software we calculate the potential solar radiation of a DEM at any resolution, e.g. 1 to 90 m2, and upscale the lower resolution climate data (e.g. 1 km2) to the same resolution using a [MT-CLIM type approximation](https://www.ntsg.umt.edu/project/mt-clim.php). The user only needs to supply or define the input DEM and the workflow will distribute the job to the HPC worker nodes through Makeflow. An output file tree is created with every upscaled climate and solar output file saved to sub-directories. Solar radiation is calculated for every day of the year at a user defined temporal step (e.g. 3-30 minute interval). To avoid Jensen’s inequality we integrate every time step, thus approximating more closely the curve of the total energy input into the CZ. This is further improved when topographic shading in complex terrain and/or urban settings are turned on.

Summary statistics are generated for each climate variable.

# Input Data

## Climatic data

### PRISM

[PRISM Climate Group](https://prism.oregonstate.edu/){target=_blank} data are available from 1980-2020.

PRISM are avaiable at 800m resolution for a $ fee, or 4KM for free.

### DAYMET

[DAYMET v4.3](https://daymet.ornl.gov/) are 1KM resolution. The data were recently released as Cloud Optimized Geotiff.

I downloaded the latest COG .tif format using a simple `wget` script

```bash
wget --verbose --no-parent --random-wait -r -nd --user=<username> ---password=<password> --accept tif --reject html,nc https://daac.ornl.gov/daacdata/daymet/Daymet_V4_Monthly_Climatology/data
```

There are ~ 240 GB of .tif data for Daymet

# Calculations for conventional EEMT

## Monthly Precipitation

$$
\operatorname{P}
$$

Units are in centimeters (cm) per month

## Local temperature correction 

Correcting temperature for local conditions

## Local Potential Evaporation-Transpiration (PET) using Hamon's

Estimating PET from local conditions

## Solar Insolation

## Mean saturated vapor pressure

## Effective Precipitation (P_e)

## Net Primary Productivity

# Calculations for Topographic correction of EEMT

## Temperature correction using solar irradiation/shading / flat surface


