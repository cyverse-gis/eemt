## History of this Project

This workflow was originally developed in 2014 at the University Arizona by undergraduate and graduate students of the [Applied Concepts in Cyberinfrastructure (ACIC)](https://pods.iplantcollaborative.org/wiki/display/ACIC/Input+from+End+User+%28Customer%29+for+product) project-based class. 

The students worked with a postdoctoral researcher ([Swetnam](https://tysonswetnam.com){target=_blank}) who had conceived the idea of distributing the calculations of solar irradiation using GRASS-GIS `r.sun` which the student's named `sol`. The output can be applied as the base energy input for a thermodynamic model called "effective energy to mass transfer" or EEMT ([Rasmussen et al. 2015](https://swes.cals.arizona.edu/chorover_lab/pdf_papers/Rasmussen_etal_2015.pdf){target=_blank}). 

The semester-long research project resulted in a parallelizable workflow tool which ran on the UArizona high performance computing (HPC) cluster. The student group also worked with [CyVerse](https://cyverse.org) (formerly iPlantCollaborative) to host the code and class wiki.

In 2015 Swetnam and his postdoctoral mentor (Pelletier) requested and were awarded an Extreme Science and Engineering Discovery Environment ([XSEDE](https://www.xsede.org/){target=_blank}) Extended Collaborative Support Service (ECSS) start-up allocation to continue the work. The result of that effort was described in [Swetnam et al. (2016)](http://dl.acm.org/citation.cfm?id=2949573){target=_blank}. 

The XSEDE ECSS was supported by a research allocation on [SDSC Comet](http://www.sdsc.edu/support/user_guides/comet.html){target=_blank} and the [Open Science Grid](http://opensciencegrid.org/). The resulting workflow was briefly made available as a tool deployed on [OpenTopography.org](http://opentopo.sdsc.edu/). That tool is now deprecated. 

The `sol` and `eemt` workflows are containerized and can be run on local machines (laptops, desktops, clusters), cloud, or HPC/HTC using [Singularity](http://singularity.lbl.gov/) and [Docker](http://docker.com).

## Sol

The ACIC student's called their project "Sol," after the solar radiation part of the model and we continue to use that naming scheme here in the repository. The `/sol/` workflow directory calculates daily and monthly global irradiation and hours of sun only.

## EEMT

EEMT is a representation of environmental energy and mass transfer doing work on the Earth's 'critical zone'. 

To learn more about the critical zone, visit the [NSF Critical Zone Observatories](http://criticalzone.org/national/) and read [Rasmussen et al. 2015](https://swes.cals.arizona.edu/chorover_lab/pdf_papers/Rasmussen_etal_2015.pdf).

[![Santa Ritas Global Insolation](https://i.ytimg.com/vi/BKCPsZBsytk/hqdefault.jpg)](https://youtu.be/BKCPsZBsytk "Santa Ritas Global Insolation")

Figure: Global insolation over 365 days calculated using GRASS r.sun

# Contents

This Github repository consists of 

(1) an [Opal2](/cyverse-gis/eemt/opal2-vm) virtual machine deployment script for running jobs on the OpenTopography, 

(2) a [Singularity](/cyverse-gis/eemt/singularity) recipe file which is hosted on [Singularity Hub](https://singularity-hub.org/), 

(3) [provisioning scripts](/provisioning) for running the workflow on cloud [Jetstream](https://jetstream-cloud.org/), and the [Open Science Grid](http://opensciencegrid.org/) HTC, 

(4) scripts for running [Sol](/cyverse-gis/eemt/sol) with [Makeflow](https://cctools.readthedocs.io/en/latest/), and 

(5) scripts for calculating [EEMT](/cyverse-gis/eemt/eemt) with Makeflow. 


## Climate Data

There are multiple sources of 1km (or less) grid climate data. Some data are observational, others are reconstructed. For the EEMT analyses we want to have a choice of which dataset from which to calculate EEMT, and eventually ensemble models. 

We use open data that can be either downloaded on the fly, or held in scratch.

# Cloudiness

[Wilson & Jetz (2016)](http://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.1002415) produced global cloudiness layers at a monthly interval from MODIS TERRA and AQUA, the data are hosted by [earthenv.org](http://www.earthenv.org/cloud).

These data are applied to the solar irradiance models to correct for cloudiness, e.g. a month with 20% cloudiness would result in an approximate 80% total irradiance value.

# North American Data

## DAYMET

Daymet v2 was the first dataset which we used to develop our spatial models. This was partly because the data were relatively easy to obtain from the DAAC website.

Currently, we are using [Daymet v3](https://daymet.ornl.gov/).

## PRISM

[PRISM](http://www.prism.oregonstate.edu/)

## NASA NEX

The 30 arc second [Downscaled Climate Projections (NEX-DCP30) dataset](https://cds.nccs.nasa.gov/nex/) report precipitation, maximum, and minimum temperature at ~800m resolution.

# Global

## NASA NEX

The [NASA NEX](https://nex.nasa.gov/nex/) project at global resolution is lower than the NEX-DCP30

## WorldClim

[Fick and Hijmans (2017)](https://www.researchgate.net/profile/Steve_Fick/publication/316999789_WorldClim_2_New_1-km_spatial_resolution_climate_surfaces_for_global_land_areas/links/591d51a30f7e9b642816e563/WorldClim-2-New-1-km-spatial-resolution-climate-surfaces-for-global-land-areas.pdf) report on (WorldClim v2](http://worldclim.org/version2) and the associated [Bioclim](http://worldclim.org/bioclim) archives are available at 30 arc seconds and are averaged from 1970-2000. Variables include monthly precipitation, maximum and minimum temperature, solar radiation, water vapor pressure, and windspeed.

## Chelsa

The [Chelsa Clim](http://chelsa-climate.org/downloads/) data ([Karger et al. 2017](https://www.nature.com/articles/sdata2017122)) include global monthly averaged climate data (precipitation, maximum and minimum temperature).

Chelsa are also preparing to host their own downscaled PMIP3 data.

# Other Satellite derived climate data

## DRI ClimateEngine

The [ClimateEngine](http://climateengine.org/) uses data from various sources, as well as Google EarthEngine. 

# Reconstructed Climate 

## CMIP

The [CMIP](http://cmip-pcmdi.llnl.gov/) uses both hindcasts and forecasts for climate out into the future. 

## PMIP

 The [PMIP3](https://pmip3.lsce.ipsl.fr/) data cover the last 12 kya of the Holocene. 


|Source|Region|Spatial|Daily?|Monthly?|Averaged?|Observation Period|T-max|T-max|Precipitation|Vapor Pressure|Albedo|Linke|
|------|------|-------|------|--------|---------|------------------|-----|-----|-------------|--------------|------|-----|
|Daymet|North America|1 km<sup>2</sup>|yes|yes|yes|1980-2016|
|Prism|CONUS|800 m<sup>2</sup>|no|yes|yes|1980-2016|
|WorldClim2|Global|30 arc sec|no|no|yes|1970-2000|
|NEX-DCP30|CONUS|30 arc sec
|NEX|Global|
|Chelsa|30 arc sec|no|no|yes|1979-2013|
|CMIP|30 - 300 arc sec|
|PMIP|


# License & Acknowledgments

All of the GIS software used by the scripts are open-source. Most are licensed under the GNU General Public License. 