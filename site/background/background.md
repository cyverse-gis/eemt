# Background 

This workflow tool was originally developed in 2014 at the University Arizona by undergraduate and graduate students of [Applied Concepts in Cyberinfrastructure (ACIC)](https://pods.iplantcollaborative.org/wiki/display/ACIC/Input+from+End+User+%28Customer%29+for+product). The students worked with a project client, Dr. Tyson Lee Swetnam, then a post-doc, who had conceived the idea as related to a research paper he was collaborating on at the time: [Rasmussen et al. 2015](https://swes.cals.arizona.edu/chorover_lab/pdf_papers/Rasmussen_etal_2015.pdf). The semester long project resulted in a parallel workflow tool run on the University's high performance computing (HPC) system. The group also worked with CyVerse (formerly iPlantCollaborative) to host the code and class wiki.

In 2015 the project received an Extreme Science and Engineering Discovery Environment ([XSEDE](https://www.xsede.org/)) Extended Collaborative Support (ECS) start-up allocation. That effort is described in [Swetnam et al. (2016)](http://dl.acm.org/citation.cfm?id=2949573). 

The XSEDE start-up allocation was followed by a research allocation on [SDSC Comet](http://www.sdsc.edu/support/user_guides/comet.html) and the [Open Science Grid](http://opensciencegrid.org/). The result of that effort is a publically available tool using the (now containerized) workflow, which is deployed on [OpenTopography.org](http://opentopo.sdsc.edu/raster?opentopoID=OTALOS.082017.4326.1#panel_sol). 

The workflow is containerized and can be run on local machines (laptops, desktops, clusters), cloud, or HPC/HTC using [Singularity](http://singularity.lbl.gov/) and [Docker](http://docker.com).

## Sol

The student's called their project "Sol", for the solar radiation they were calculating, and we continue to use that naming scheme here in the repository. The `/cyverse-gis/eemt/sol` scripting calculates daily and monthly global irradiation and hours of sun.

## EEMT

Effective Energy and Mass Transfer (EEMT) is a representation of environmental energy and mass transfer doing work on the Earth's 'critical zone'. To learn more about the critical zone, visit the [NSF Critical Zone Observatories](http://criticalzone.org/national/) and read [Rasmussen et al. 2015](https://swes.cals.arizona.edu/chorover_lab/pdf_papers/Rasmussen_etal_2015.pdf).

[![Santa Ritas Global Insolation](https://i.ytimg.com/vi/BKCPsZBsytk/hqdefault.jpg)](https://youtu.be/BKCPsZBsytk "Santa Ritas Global Insolation")

###### Figure: Global insolation over 365 days calculated using GRASS r.sun.

# Contents

This Github repository consists of (1) an [Opal2](/cyverse-gis/eemt/opal2-vm) virtual machine deployment script for running jobs on the OpenTopography, (2) a [Singularity](/cyverse-gis/eemt/singularity) recipe file which is hosted on [Singularity Hub](https://singularity-hub.org/), (3) [provisioning scripts](/provisioning) for running the workflow on cloud [Jetstream](https://jetstream-cloud.org/), and the [Open Science Grid](http://opensciencegrid.org/) HTC, (4) scripts for running [Sol](/cyverse-gis/eemt/sol) with [Makeflow](https://ccl.cse.nd.edu/software/makeflow/), and (5) scripts for calculating [EEMT](/cyverse-gis/eemt/eemt) with Makeflow. 

## Workflow 

On a small VM or workstation.

Pull this repository:

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

Climate data are available from numerous organizations, e.g. [Daymet, WorldClim, Chelsa](https://github.com/cyverse-gis/eemt/wiki/Climate-Data). These data are used in the EEMT calculation.

# License & Acknowledgments

All of the GIS software used by the scripts are open-source. Most are licensed under the GNU General Public License. 