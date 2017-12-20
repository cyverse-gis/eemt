# eemt-provisioning

Scripts to be called from cron with a single argument, the Makeflow/WorkQueue password.
For example, OSG and Comet can be configured on the OSG submit host:

```
*/5 * * * *  (cd ~/git/eemt/provisioning && ./osg-workers-on-demand.cron Some_Secret) >~/logs/osg.log.last 2>&1
*/12 * * * *  (cd ~/git/eemt/provisioning && ./comet-workers-on-demand.cron Some_Secret) >~/logs/comet.log.last 2>&1

```

## Singularity image

The master copy of the image is on Singularity Hub

    singularity pull shub://tyson-swetnam/eemt-singularity-dev:master

The image is pulled every few hours and also made available at:

    http://xd-login.opensciencegrid.org/scratch/eemt/singularity/eemt-current.img


