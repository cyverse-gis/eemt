Repository with code for modelling Effective Energy to Mass Transfer (EEMT)([Rasmussen et al. 2015]( https://doi.org/10.2136/vzj2014.07.0102)) using OSGEO open source software and workflow manager. 

MkDocs website: https://tyson-swetnam.github.io/eemt

[author copy Rasmussen et al. pdf](http://geomorphology.sese.asu.edu/Papers/Rasmussen_et_al_VadoseZJ_EEMT_2015.pdf)

# Contents

## .github

Contains GitHub Actions for building webpages and docker images

## docs

Documentation written in MkDocs markdown syntax, rendered as github.io pages

## docker

Dockerfile build

## eemt

Makeflow workflow manager for running full EEMT pipeline

## sol

Makeflow workflow manager for running GRASS-GIS solar irradation `r.sun.mp` model with multicore processing.


-----------------------------------------------------------------------

**Funding and Citations:**

This research was supported by the U.S. National Science Foundation Grants EAR0724958630 and EAR-1331408 provided in support of the Catalina-Jemez Critical Zone Observatory.

CyVerse is funded entirely by the [National Science Foundation](https://nsf.gov) under Award Numbers:

[![NSF-0735191](https://img.shields.io/badge/NSF-0735191-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=0735191)  [![NSF-1265383](https://img.shields.io/badge/NSF-1265383-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1265383)  [![NSF-1743442](https://img.shields.io/badge/NSF-1743442-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1743442)

[![DOI](https://img.shields.io/badge/Zenodo-CyVerse%20Community-blue)](https://zenodo.org/communities/cyverse)

The CyVerse Zenodo Community has published, citable versions of CyVerse materials.

Please cite CyVerse appropriately when you make use of our resources; see [CyVerse citation policy](https://cyverse.org/policies/cite-cyverse).
