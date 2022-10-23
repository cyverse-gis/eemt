## Makeflow / Work Queue Workflows

Our workflow utilizes the [Cooperative Computing Tools](https://cctools.readthedocs.io/en/latest/){target=_blank} Makeflow and Work Queue

[![make-flow](https://cctools.readthedocs.io/en/latest/logos/makeflow-logo.png)](https://cctools.readthedocs.io/en/latest/makeflow/){target=_blank}
[![work-queue](https://cctools.readthedocs.io/en/latest/logos/workqueue-logo.png)](https://cctools.readthedocs.io/en/latest/work_queue/){target=_blank}

We are running a `factory` on a virtual machine which checks for jobs every five minutes. When a task is detected, nodes are requested either locally, or optionally from distributed platforms, like the Open Science Grid (OSG). Workers on OSG are run on individual nodes (set to cores = 4) and more are added every five minutes until there are no more waiting tasks.

When the task is complete, the workers are released and jobs that are ended go back to the OSG pool, auto-scaling the workflow up and then back down. 

### Terminology

`factory`: a workflow monitor that coordinates the supervisor, workers, and tasks

`job`: a request sent to a high performance or high throughput computing scheduler for a computational resource

`task`: an execution in the workflow, e.g. to process a single day of solar irradiation, or to calculate a monthly total of irradiation

`worker`: process that monitors an individual task, can be reassigned new tasks as old tasks complete

`supervisor`: a process that controls the tasks that each worker is assigned
## Instructions


## Workflow Steps

```
git clone https://cyverse-gis/eemt
```

Start the master:

```
./eemt/sol/run-master eemt/sol/examples/mcn_10m.tif
```

Start the worker:

```
./eemt/sol/run-worker EEMT
```

## Run GRASS, QGIS, Saga-GIS GUI

Download the OSGEO GIS Singularity container to run locally.

```
singularity pull --name osgeo.simg shub://tyson-swetnam/osgeo-singularity
```

then

```
singularity exec osgeo.simg qgis
```

or

```
singularity exec shub://tyson-swetnam/osgeo-singularity qgis
```

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
