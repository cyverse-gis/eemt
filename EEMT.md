# Effective Energy and Mass Transfer (EEMT) Algorithm

## Overview

The Effective Energy and Mass Transfer (EEMT) algorithm quantifies energy and mass flux within the Critical Zone to understand landscape evolution and biogeochemical processes. EEMT provides a common energy currency (W m⁻²) for comparing diverse environmental processes across spatiotemporal scales.

## Fundamental Equation

The core EEMT equation calculates the available free energy for physical and chemical work in the Critical Zone:

```
EEMT = E_BIO + E_PPT [W m⁻²]
```

Where:
- **E_BIO** = Energy flux from net primary production (biological energy)
- **E_PPT** = Energy flux from effective precipitation (thermal energy)

## Spatio-temporal Input Parameters

### Digital Elevation Models (DEM)
- **Resolution**: 10 cm² to 90 m² spatial resolution
- **Format**: GeoTIFF (.tif) format required
- **Sources**: Lidar DSM, SRTM, ASTER GDEM, or custom topographic data
- **Purpose**: Calculates slope, aspect, and topographic complexity for solar radiation modeling

### Solar Radiation Parameters

#### Temporal Resolution
- **Daily calculations**: 365 daily solar irradiation models per year
- **Time step interval**: 3-15 minutes (configurable based on spatial resolution)
  - High resolution (10 cm²): 3-minute intervals for forest canopy analysis
  - Regional scale (90 m²): 15-minute intervals for landscape analysis

#### Atmospheric Parameters
- **Linke turbidity coefficient** (`--linke_value`): Atmospheric clarity factor
  - Range: 1.0-8.0
  - Default: ~3.0 for clear atmospheric conditions
  - Higher values indicate more atmospheric pollution/water vapor

- **Surface albedo** (`--albedo_value`): Surface reflectance coefficient  
  - Range: 0.0-1.0
  - Typical values: 0.15-0.25 for vegetation, 0.8+ for snow
  - Default: 0.2 for mixed vegetation

### Climate Data (DAYMET Integration)

#### Temperature Variables
- **Minimum daily temperature** (tmin): °C
- **Maximum daily temperature** (tmax): °C  
- **Temporal range**: 1980-present (DAYMET availability)
- **Spatial resolution**: 1 km grid
- **Purpose**: Calculates thermal energy content of precipitation

#### Precipitation Variables
- **Daily precipitation** (prcp): mm/day
- **Effective precipitation**: P - ET - Surface runoff
- **Energy conversion**: E_PPT = F × c_w × ΔT [W m⁻²]
  - F = mass flux of effective precipitation [kg m⁻² s⁻¹]
  - c_w = specific heat of water [J kg⁻¹ K⁻¹] 
  - ΔT = T_ambient - T_ref (273K)

#### Vapor Pressure
- **Daily vapor pressure** (vp): Pa
- **Purpose**: Atmospheric moisture content for evapotranspiration calculations

### Biomass and Primary Production

#### Net Primary Production (NPP)
- **Calculation**: GPP - Plant respiration
- **Units**: kg C m⁻² s⁻¹
- **Energy conversion**: E_BIO = NPP × h_BIO [W m⁻²]
  - h_BIO = specific biomass enthalpy (22 × 10⁶ J kg⁻¹)

#### Photosynthetically Active Radiation (PAR)
- **Source**: r.sun.mp calculations in GRASS GIS
- **Daily integration**: Accounts for topographic shading and atmospheric effects
- **Solar geometry**: Precise sun angle calculations for each day of year

### Topographic Derivatives

#### Slope and Aspect
- **Calculation**: r.slope.aspect in GRASS GIS
- **Units**: Decimal degrees
- **Purpose**: Solar radiation modeling and flow direction analysis

#### Topographic Wetness Index (TWI)
- **Formula**: ln(A / tan(β))
- **Where**: A = upslope contributing area, β = slope angle
- **Purpose**: Quantifies water accumulation potential

### Computational Parameters

#### Parallelization
- **Thread count** (`--num_threads`): Number of parallel processing cores
- **Default**: 4 threads
- **Scaling**: Up to 365 workers for daily solar calculations
- **Memory allocation**: 1000 MB per thread minimum

#### Workflow Management
- **Engine**: Makeflow + Work Queue (CCTools)
- **Batch systems**: Compatible with OSG, SLURM, PBS, HTCondor
- **Fault tolerance**: Built-in retry mechanisms and checkpointing

## Energy Balance Framework

### Flow Exergy Components
The total energy flux through the Critical Zone:

```
K = E_ET + E_PPT + E_BIO + E_ELV + E_GEO + ζ [W m⁻²]
```

Where:
- **E_ET**: Latent heat flux from evapotranspiration
- **E_ELV**: Energy flux from physical denudation (uplift)
- **E_GEO**: Energy flux from chemical denudation
- **ζ**: Additional energy inputs (dust, anthropogenic)

### Critical Thresholds
- **EEMT transition**: ~70 MJ m⁻² yr⁻¹
- **F_BIO = 0.5**: Transition from carbon-dominated to water-dominated systems
- **Below threshold**: Water-limited systems (E_BIO dominant)
- **Above threshold**: Energy-limited systems (E_PPT dominant)

## Output Products

### Solar Radiation Maps
- **Global radiation**: Total daily/monthly solar irradiation (Wh)
- **Flat terrain**: Solar irradiation without topographic effects
- **Hours of sunlight**: Direct illumination duration

### EEMT Results
- **Topographic EEMT**: Including terrain effects
- **Traditional EEMT**: Flat terrain equivalent
- **Monthly and annual summaries**
- **Multi-year time series** (1980-present)

## Model Applications

1. **Soil formation rates**: Correlation with chemical weathering
2. **Landscape denudation**: Physical and chemical mass flux
3. **Critical Zone evolution**: Long-term landscape development
4. **Carbon cycling**: Primary production and decomposition rates
5. **Hydrologic partitioning**: ET, runoff, and subsurface flow
6. **Climate change impacts**: Sensitivity to temperature and precipitation changes

## Data Requirements Summary

| Parameter | Source | Resolution | Time Period | Format |
|-----------|--------|------------|-------------|--------|
| DEM | Lidar/SRTM | 0.1m-90m | Static | GeoTIFF |
| Temperature | DAYMET | 1km daily | 1980-present | NetCDF/GeoTIFF |
| Precipitation | DAYMET | 1km daily | 1980-present | NetCDF/GeoTIFF |
| Vapor Pressure | DAYMET | 1km daily | 1980-present | NetCDF/GeoTIFF |
| Solar Parameters | r.sun | Variable | Daily/Annual | Calculated |

## References

Based on theoretical framework from:
- Rasmussen et al. (2011): Open system thermodynamics for Critical Zone integration
- Swetnam et al. (2016): Scaling GIS analysis from desktop to cloud computing
- Pelletier et al. (2017): Quantifying topographic and vegetation effects on energy/mass transfer