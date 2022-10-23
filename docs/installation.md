Installation of the required GIS software environment for calculating the models can be done locally, using `conda` or `mamba` package managers, or with Docker, or by using a `makefile`

## Docker

Our cached Docker Image is maintained on this GitHub repository, and uses an Action to build and cache the container on CyVerse Harbor.

```
docker pull harbor.cyverse.org/vice/jupyter/eemt:latest 
```

```
docker run -it --rm -p 8888:8888 harbor.cyverse.org/vice/jupyter/eemt:latest
```

## Makefile

## Conda

We recommend installing `mamba` and then installing the `environment.yml` for the geospatial environment

```
mamba env create eemt -f environment.yml
```

```
conda activate eemt
```

## Developer Notes

### GIS

https://grasswiki.osgeo.org/wiki/Compile_and_Install

https://github.com/OSGeo/grass/blob/main/INSTALL.md 

Installation order for building GRASS-GIS must be done sequentially:

1. PROJ
2. GDAL-OGR (compiled without GRASS support)
3. PostgreSQL, MySQL, sqlite (optional)
4. GRASS GIS
5. GDAL-OGR-GRASS plugin (optional)

### Makeflow & WorkQueue

