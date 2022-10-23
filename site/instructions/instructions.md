## Workflow

Our workflow utilizes the [Cooperative Computing Tools](https://cctools.readthedocs.io/en/latest/) Makeflow and WorkQueue workflow managers.

We are running a `factory` on a CyVerse virtual machine which checks for jobs every five minutes. When a task is detected, nodes are requested from the Open Science Grid (OSG). 

Workers on OSG are run on each node (cores = 4) and more are added every five minutes until there are no more waiting tasks.

When the task is complete, the workers are released and jobs that are ended go back to the OSG pool. 

# Terminology

`factory`: a workflow monitor that coordinates the supervisor, workers, and tasks

`job`: a request sent to a high performance or high throughput computing scheduler for a computational resource

`task`: an execution in the workflow, e.g. to process a single day of solar irradiation, or to calculate a monthly total of irradiation

`worker`: process that monitors an individual task, can be reassigned new tasks as old tasks complete

`supervisor`: a process that controls the tasks that each worker is assigned
## Instructions

