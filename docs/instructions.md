To calculate traditional and topographically controlled "Effective Energy and Mass Transfer (EEMT)" ([Rasmussen et al. 2015](https://dl.sciencesocieties.org/publications/vzj/pdfs/0/0/vzj2014.07.0102){target=_blank}), which is a measure of the available free energy for physical and chemical work [units in mega joules per meter square over time: [$MJ m^2 yr_{-1}$], at the surface of the critical zone.

To calculate EEMT we use a digital elevation model (DEM) and monthly averaged precipitation, vapor pressure, and temperature series. With open-source GIS software we calculate the potential solar radiation of a DEM at any resolution, e.g. $1-90 m^2$ and upscale the lower resolution climate data (e.g. $1 km^2$) to the same resolution using a [MT-CLIM type approximation](https://www.ntsg.umt.edu/project/mt-clim.php){target=_blank}. 

The user only needs to supply or define the input DEM and the workflow will distribute the job to the HPC worker nodes through Makeflow. 

An output file tree is created with every upscaled climate and solar output file saved to sub-directories. 

Solar radiation is calculated for every day of the year at a user defined temporal step (e.g. 3-30 minute interval). 

To avoid Jensen’s inequality we integrate every time step, thus approximating more closely the curve of the total energy input into the CZ. 

This is further improved when topographic shading in complex terrain and/or urban settings are turned on.

## Makeflow & Work Queue workflow managers

Our automated workflow utilizes the [Cooperative Computing Tools](https://cctools.readthedocs.io/en/latest/){target=_blank} Makeflow and Work Queue

[![makeflow](https://cctools.readthedocs.io/en/latest/logos/makeflow-logo.png){width="300"}](https://cctools.readthedocs.io/en/latest/makeflow/){target=_blank}
[![workqueue](https://cctools.readthedocs.io/en/latest/logos/workqueue-logo.png){width="300"}](https://cctools.readthedocs.io/en/latest/work_queue/){target=_blank}

We are running a `factory` on a virtual machine which checks for jobs every five minutes. When a task is detected, nodes are requested either locally, or optionally from distributed platforms, like the Open Science Grid (OSG). Workers on OSG are run on individual nodes (set to cores = 4) and more are added every five minutes until there are no more waiting tasks.

When the task is complete, the workers are released and jobs that are ended go back to the OSG pool, auto-scaling the workflow up and then back down. 

### Terminology

`factory`: a workflow monitor that coordinates the supervisor, workers, and tasks

`job`: a request sent to a high performance or high throughput computing scheduler for a computational resource

`task`: an execution in the workflow, e.g. to process a single day of solar irradiation, or to calculate a monthly total of irradiation

`worker`: process that monitors an individual task, can be reassigned new tasks as old tasks complete

`supervisor`: a process that controls the tasks that each worker is assigned

## Instructions for running `sol` solar radiation calculations

### :material-form-textbox-password: Create a password

The workflow manager uses a simple workqueue password to prevent worker resources from being used by other actors. 

The password must be set prior to running the workflow.

```
echo "new_password" >> ~/.eemt-makeflow-password
```

### :simple-github: Download the `git` repository from GitHub

```
git clone https://cyverse-gis/eemt
```

### :simple-gnometerminal: Start the workflow

Start the workflow master using a sample DEM

```
./eemt/sol/run-master eemt/sol/examples/mcn_10m.tif
```

To run the workflow with a real DEM, select any .tif file on your local host.

Starting a workflow worker:

```
./eemt/sol/run-worker EEMT
```

