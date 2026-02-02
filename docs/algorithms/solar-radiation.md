---
title: Solar Radiation Algorithms
description: Comprehensive documentation of the solar radiation modeling algorithms used in EEMT
---

# Solar Radiation Algorithms

## Overview

Solar radiation is the primary energy input driving all Critical Zone processes. The EEMT framework uses the GRASS GIS `r.sun` module with multi-threaded processing (`nprocs` parameter) to calculate topographically-modified solar radiation, accounting for slope, aspect, atmospheric conditions, and terrain shadowing effects.

## Mathematical Foundation

### Clear-Sky Solar Radiation

The theoretical maximum solar radiation reaching Earth's atmosphere is determined by:

$$I_0 = S_c \left( \frac{r_0}{r} \right)^2$$

Where:
- **I₀** = Extraterrestrial radiation [W m⁻²]
- **S<sub>c</sub>** = Solar constant (1367 W m⁻²)
- **r₀/r** = Earth-Sun distance ratio (varies seasonally)

### Atmospheric Attenuation

Solar radiation is attenuated as it passes through the atmosphere. The EEMT framework uses the **Linke Turbidity Factor** to account for atmospheric effects:

$$T_L = \frac{\delta_{atm}}{\delta_{clean}}$$

Where:
- **T<sub>L</sub>** = Linke turbidity factor [dimensionless]
- **δ<sub>atm</sub>** = Optical thickness of real atmosphere
- **δ<sub>clean</sub>** = Optical thickness of clean, dry atmosphere

Typical Linke turbidity values:
- **1.0-2.0**: Very clean, cold air (Arctic, high mountains)
- **2.0-3.0**: Clean air (rural areas, moderate elevations)
- **3.0-4.0**: Moderate turbidity (temperate regions)
- **4.0-5.0**: Turbid atmosphere (urban, humid areas)
- **5.0-8.0**: Very turbid (polluted urban, tropical)

## Core Algorithm: r.sun

### Algorithm Components

The `r.sun` module calculates solar radiation using three primary components:

#### 1. Direct (Beam) Radiation

Direct radiation reaching a tilted surface:

$$I_{direct} = I_0 \cdot \tau_b \cdot \cos(\theta_i)$$

Where:
- **τ<sub>b</sub>** = Beam transmittance through atmosphere
- **θ<sub>i</sub>** = Angle of incidence between sun rays and surface normal

The angle of incidence is calculated as:

$$\cos(\theta_i) = \cos(\beta)\cos(Z) + \sin(\beta)\sin(Z)\cos(\phi_s - \phi_n)$$

Where:
- **β** = Surface slope angle [degrees]
- **Z** = Solar zenith angle [degrees]
- **φ<sub>s</sub>** = Solar azimuth [degrees]
- **φ<sub>n</sub>** = Surface aspect [degrees]

#### 2. Diffuse (Sky) Radiation

Diffuse radiation from atmospheric scattering:

$$I_{diffuse} = I_0 \cdot \tau_d \cdot F_{sky}$$

Where:
- **τ<sub>d</sub>** = Diffuse transmittance
- **F<sub>sky</sub>** = Sky view factor (portion of sky visible from surface)

The sky view factor accounts for terrain obstruction:

$$F_{sky} = \frac{1}{2\pi} \int_0^{2\pi} \cos^2(H(\phi)) \, d\phi$$

Where **H(φ)** is the horizon angle in direction φ.

#### 3. Reflected Radiation

Radiation reflected from surrounding terrain:

$$I_{reflected} = \rho \cdot (I_{direct} + I_{diffuse}) \cdot F_{terrain}$$

Where:
- **ρ** = Surface albedo (reflectance)
- **F<sub>terrain</sub>** = Terrain view factor

### Total Solar Radiation

The total radiation received by a surface is:

$$I_{total} = I_{direct} + I_{diffuse} + I_{reflected}$$

## Horizon Calculation

### Horizon Effects

Terrain shadowing significantly affects solar radiation receipt. The horizon angle determines when direct sunlight is blocked:

$$H(\phi) = \max_{d} \left( \arctan \left( \frac{z(d,\phi) - z_0}{d} \right) \right)$$

Where:
- **H(φ)** = Horizon angle in direction φ
- **z(d,φ)** = Elevation at distance d in direction φ
- **z₀** = Elevation at calculation point
- **d** = Distance from calculation point

### Shadow Calculation

A point is in shadow when:

$$h_{sun} < H(\phi_{sun})$$

Where:
- **h<sub>sun</sub>** = Solar elevation angle
- **H(φ<sub>sun</sub>)** = Horizon angle in sun direction

## Implementation Details

### Temporal Resolution

The EEMT framework calculates solar radiation at regular time intervals throughout each day:

```python
def calculate_daily_solar(dem, day_of_year, step_minutes=15):
    """
    Calculate solar radiation for one day
    
    Parameters:
    - dem: Digital elevation model
    - day_of_year: Julian day (1-365)
    - step_minutes: Time step for calculation (3-60 minutes)
    
    Returns:
    - Daily total solar radiation [Wh m⁻²]
    """
    
    # Solar declination
    declination = 23.45 * sin(360 * (284 + day_of_year) / 365)
    
    # Calculate sunrise and sunset times
    sunrise, sunset = calculate_sun_times(latitude, declination)
    
    # Time loop
    total_radiation = 0
    for time in range(sunrise, sunset, step_minutes):
        
        # Solar position
        zenith, azimuth = solar_position(time, day_of_year, latitude, longitude)
        
        # Check for shadows
        if not in_shadow(zenith, azimuth, horizon):
            
            # Calculate radiation components
            direct = calculate_direct(zenith, azimuth, slope, aspect)
            diffuse = calculate_diffuse(sky_view_factor)
            reflected = calculate_reflected(albedo, terrain_view_factor)
            
            # Sum components
            instantaneous = direct + diffuse + reflected
            
            # Integrate over time step
            total_radiation += instantaneous * (step_minutes * 60)  # Convert to seconds
    
    return total_radiation / 3600  # Convert to Wh
```

### Annual Integration

Annual solar radiation is calculated by summing daily values:

```python
def calculate_annual_solar(dem, year, step_minutes=15):
    """
    Calculate annual solar radiation
    
    Returns:
    - Annual solar radiation maps for each day
    - Monthly summaries
    - Annual total [MJ m⁻² yr⁻¹]
    """
    
    daily_radiation = []
    
    # Calculate for each day
    for day in range(1, 366):
        daily = calculate_daily_solar(dem, day, step_minutes)
        daily_radiation.append(daily)
    
    # Monthly aggregation
    monthly_radiation = aggregate_to_monthly(daily_radiation)
    
    # Annual total
    annual_total = sum(daily_radiation) * 0.0036  # Convert Wh to MJ
    
    return {
        'daily': daily_radiation,
        'monthly': monthly_radiation, 
        'annual': annual_total
    }
```

## Parameter Optimization

### Step Size Selection

The time step affects accuracy and computational cost:

| Step Size | Accuracy | Computation Time | Recommended Use |
|-----------|----------|------------------|-----------------|
| 3 min | Very High | Very Long | Research, small areas |
| 5 min | High | Long | Detailed analysis |
| 10 min | Good | Moderate | Standard analysis |
| 15 min | Adequate | Fast | Large areas |
| 30 min | Low | Very Fast | Preliminary analysis |

### Atmospheric Parameters

#### Linke Turbidity Estimation

For areas without measurements, estimate Linke turbidity from:

```python
def estimate_linke_turbidity(elevation, latitude, month):
    """
    Estimate Linke turbidity factor
    
    Based on Remund et al. (2003) global climatology
    """
    
    # Base turbidity at sea level
    if abs(latitude) > 60:
        base_turbidity = 2.0  # Polar regions
    elif abs(latitude) > 35:
        base_turbidity = 3.0  # Temperate regions
    else:
        base_turbidity = 4.0  # Tropical regions
    
    # Elevation correction (decrease with altitude)
    elevation_correction = -0.5 * (elevation / 1000)
    
    # Seasonal variation
    seasonal_factor = 1 + 0.3 * sin(2 * pi * (month - 3) / 12)
    
    # Final estimate
    linke = base_turbidity + elevation_correction
    linke *= seasonal_factor
    
    return max(1.0, min(8.0, linke))  # Constrain to valid range
```

#### Surface Albedo Values

Typical albedo values for different surfaces:

| Surface Type | Albedo Range | EEMT Default |
|--------------|--------------|--------------|
| Fresh snow | 0.80-0.95 | 0.85 |
| Old snow | 0.40-0.70 | 0.55 |
| Desert sand | 0.30-0.40 | 0.35 |
| Bare soil | 0.15-0.25 | 0.20 |
| Grassland | 0.15-0.25 | 0.20 |
| Forest | 0.10-0.20 | 0.15 |
| Water | 0.05-0.10 | 0.07 |

## Topographic Effects

### Slope and Aspect Modification

Radiation varies strongly with topography:

$$R_{ratio} = \frac{I_{slope}}{I_{flat}}$$

This ratio can range from:
- **0.0**: Complete shading (north-facing cliffs)
- **0.5**: Reduced radiation (pole-facing slopes)
- **1.0**: Same as flat surface
- **1.5**: Enhanced radiation (equator-facing slopes)
- **2.0+**: Maximum enhancement (optimal slope/aspect)

### Elevation Effects

Solar radiation increases with elevation due to:

1. **Reduced atmospheric path length**
2. **Lower atmospheric turbidity**
3. **Decreased water vapor content**

Approximate increase: **+7% per 1000m elevation**

## Quality Control

### Validation Checks

```python
def validate_solar_output(radiation_map):
    """
    Quality control for solar radiation calculations
    """
    
    checks = {
        'range': check_physical_limits(radiation_map),
        'spatial': check_spatial_consistency(radiation_map),
        'temporal': check_temporal_patterns(radiation_map),
        'topographic': check_topographic_effects(radiation_map)
    }
    
    return checks

def check_physical_limits(radiation):
    """
    Ensure radiation values are physically reasonable
    """
    
    # Maximum theoretical clear-sky radiation
    max_theoretical = 1367  # W/m² (solar constant)
    
    # Typical annual totals (MJ/m²/yr)
    min_annual = 1000  # Polar regions
    max_annual = 9000  # Desert regions
    
    return {
        'instantaneous_valid': radiation.max() < max_theoretical,
        'annual_range_valid': min_annual < radiation.sum() < max_annual
    }
```

## Common Issues and Solutions

### Issue: Unrealistic radiation values

**Symptoms**: Radiation exceeds physical limits or shows artifacts

**Solutions**:
1. Check DEM units and projection
2. Verify Linke turbidity is appropriate for region
3. Ensure time step is adequate for latitude
4. Check for DEM artifacts or errors

### Issue: Edge effects

**Symptoms**: Incorrect radiation near DEM boundaries

**Solutions**:
1. Buffer DEM by horizon calculation distance
2. Use larger DEM extent than study area
3. Apply edge correction algorithms

### Issue: Computational performance

**Symptoms**: Calculations take excessive time

**Solutions**:
1. Increase time step (reduce from 5 to 15 minutes)
2. Tile large DEMs for parallel processing
3. Use monthly representative days instead of full year
4. Enable GPU acceleration if available

## References

- Hofierka, J., & Suri, M. (2002). The solar radiation model for Open source GIS: implementation and applications. *Proceedings of the Open source GIS-GRASS users conference*.

- Remund, J., et al. (2003). Worldwide Linke turbidity information. *Proceedings of ISES Solar World Congress*.

- Ruiz‐Arias, J. A., et al. (2009). A comparative analysis of DEM‐based models to estimate the solar radiation in mountainous terrain. *International Journal of Geographical Information Science*, 23(8), 1049-1076.

---

*Next: [Climate Integration →](climate-integration.md)*