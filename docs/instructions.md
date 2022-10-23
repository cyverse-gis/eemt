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
