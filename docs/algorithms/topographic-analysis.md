---
title: Topographic Analysis Algorithms
description: Detailed documentation of topographic indices and flow routing algorithms used in EEMT
---

# Topographic Analysis Algorithms

## Overview

Topographic analysis in EEMT quantifies how landscape morphology controls water flow, energy distribution, and mass transfer processes. The framework implements multiple topographic indices including the Topographic Wetness Index (TWI), Mass Conservative Wetness Index (MCWI), and various flow routing algorithms.

## Topographic Wetness Index (TWI)

### Mathematical Definition

The Topographic Wetness Index quantifies the tendency of water to accumulate at any point in the landscape:

$$TWI = \ln\left(\frac{A_s}{\tan\beta}\right)$$

Where:
- **A<sub>s</sub>** = Specific contributing area [m²/m] (upslope area per unit contour width)
- **β** = Local slope angle [radians]
- **tan(β)** = Local slope gradient

### Physical Interpretation

TWI values indicate moisture conditions:

| TWI Range | Interpretation | Typical Locations |
|-----------|---------------|-------------------|
| < 4 | Very dry | Ridges, steep slopes |
| 4-6 | Dry | Upper hillslopes |
| 6-8 | Moderate | Mid-slopes |
| 8-10 | Moist | Lower slopes, flats |
| 10-12 | Wet | Convergent areas |
| > 12 | Very wet | Valley bottoms, streams |

### Implementation

```python
def calculate_twi(dem, flow_accumulation=None):
    """
    Calculate Topographic Wetness Index
    
    Parameters:
    - dem: Digital elevation model
    - flow_accumulation: Pre-calculated flow accumulation (optional)
    
    Returns:
    - twi: Topographic wetness index
    """
    
    # Calculate slope in radians
    slope_degrees = calculate_slope(dem)
    slope_radians = np.deg2rad(slope_degrees)
    
    # Avoid division by zero
    slope_radians = np.maximum(slope_radians, 0.001)
    
    # Calculate flow accumulation if not provided
    if flow_accumulation is None:
        flow_accumulation = calculate_flow_accumulation(dem)
    
    # Get cell size
    cell_size = get_cell_size(dem)
    
    # Specific contributing area (m²/m)
    # Flow accumulation × cell area / cell width
    specific_area = flow_accumulation * cell_size
    
    # TWI calculation
    twi = np.log(specific_area / np.tan(slope_radians))
    
    # Handle invalid values
    twi[np.isinf(twi)] = np.nan
    twi[twi < 0] = 0
    
    return twi
```

## Mass Conservative Wetness Index (MCWI)

### Theoretical Foundation

The MCWI improves upon TWI by ensuring mass conservation across the landscape:

$$MCWI_i = TWI_i \times \frac{\bar{P}}{\bar{TWI}}$$

Where:
- **MCWI<sub>i</sub>** = Mass conservative wetness index at location i
- **TWI<sub>i</sub>** = Traditional wetness index at location i
- **P̄** = Mean precipitation over the domain
- **TWI** = Mean TWI over the domain

This normalization ensures:

$$\sum_{i=1}^{n} MCWI_i = \sum_{i=1}^{n} P_i$$

### Enhanced MCWI with Precipitation

For spatially variable precipitation:

```python
def calculate_mcwi(twi, precipitation=None):
    """
    Calculate Mass Conservative Wetness Index
    
    Parameters:
    - twi: Topographic wetness index
    - precipitation: Spatial precipitation field (optional)
    
    Returns:
    - mcwi: Mass conservative wetness index
    """
    
    if precipitation is None:
        # Assume uniform precipitation
        precipitation = np.ones_like(twi)
    
    # Calculate means
    mean_twi = np.nanmean(twi)
    mean_precip = np.nanmean(precipitation)
    
    # Normalize TWI to conserve mass
    mcwi = twi * (mean_precip / mean_twi)
    
    # Apply precipitation weighting
    mcwi = mcwi * (precipitation / mean_precip)
    
    # Verify mass conservation
    total_input = np.nansum(precipitation)
    total_output = np.nansum(mcwi)
    conservation_error = abs(total_input - total_output) / total_input
    
    if conservation_error > 0.01:  # 1% tolerance
        print(f"Warning: Mass conservation error = {conservation_error:.2%}")
    
    return mcwi
```

### Lateral Redistribution

MCWI enables lateral water redistribution:

```python
def redistribute_water_mcwi(precipitation, mcwi, convergence_factor=1.0):
    """
    Redistribute water based on MCWI
    
    Parameters:
    - precipitation: Input precipitation field
    - mcwi: Mass conservative wetness index
    - convergence_factor: Strength of redistribution (0=none, 1=full)
    
    Returns:
    - redistributed: Water after lateral redistribution
    """
    
    # Normalize MCWI to [0, 1]
    mcwi_norm = (mcwi - np.nanmin(mcwi)) / (np.nanmax(mcwi) - np.nanmin(mcwi))
    
    # Calculate redistribution weights
    weights = convergence_factor * mcwi_norm + (1 - convergence_factor)
    
    # Ensure mass conservation
    weights = weights * (np.nansum(precipitation) / np.nansum(precipitation * weights))
    
    # Apply redistribution
    redistributed = precipitation * weights
    
    return redistributed
```

## Flow Accumulation Algorithms

### D8 (Eight-Direction) Flow

The simplest flow routing method, directing all flow to the steepest downslope neighbor:

```python
def d8_flow_direction(dem):
    """
    D8 flow direction algorithm
    
    Returns flow direction codes:
    32  64  128
    16  X   1
    8   4   2
    """
    
    # Define neighbor offsets
    neighbors = [
        (-1, 1, 32), (0, 1, 64), (1, 1, 128),
        (-1, 0, 16),              (1, 0, 1),
        (-1, -1, 8), (0, -1, 4), (1, -1, 2)
    ]
    
    flow_dir = np.zeros_like(dem, dtype=np.int32)
    
    for i in range(dem.shape[0]):
        for j in range(dem.shape[1]):
            
            max_drop = 0
            direction = 0
            
            for di, dj, code in neighbors:
                ni, nj = i + di, j + dj
                
                if 0 <= ni < dem.shape[0] and 0 <= nj < dem.shape[1]:
                    # Calculate slope
                    distance = np.sqrt(di**2 + dj**2) * cell_size
                    drop = (dem[i, j] - dem[ni, nj]) / distance
                    
                    if drop > max_drop:
                        max_drop = drop
                        direction = code
            
            flow_dir[i, j] = direction
    
    return flow_dir
```

### D-Infinity (Continuous Flow Direction)

D-infinity allows flow dispersion across multiple neighbors:

```python
def dinf_flow_direction(dem):
    """
    D-infinity flow direction algorithm
    
    Returns:
    - flow_angle: Flow direction in radians (0-2π)
    - slope: Maximum downslope gradient
    """
    
    # Calculate slopes to 8 neighbors
    e0 = dem[1:-1, 2:] - dem[1:-1, 1:-1]    # E
    e1 = dem[:-2, 2:] - dem[1:-1, 1:-1]     # NE
    e2 = dem[:-2, 1:-1] - dem[1:-1, 1:-1]   # N
    e3 = dem[:-2, :-2] - dem[1:-1, 1:-1]    # NW
    e4 = dem[1:-1, :-2] - dem[1:-1, 1:-1]   # W
    e5 = dem[2:, :-2] - dem[1:-1, 1:-1]     # SW
    e6 = dem[2:, 1:-1] - dem[1:-1, 1:-1]    # S
    e7 = dem[2:, 2:] - dem[1:-1, 1:-1]      # SE
    
    # Calculate flow angle for each triangular facet
    flow_angles = []
    slopes = []
    
    for k in range(8):
        # Get adjacent edges
        e1_k = eval(f'e{k}')
        e2_k = eval(f'e{(k+1)%8}')
        
        # Calculate flow direction within facet
        angle, slope = calculate_facet_flow(e1_k, e2_k, k)
        flow_angles.append(angle)
        slopes.append(slope)
    
    # Select steepest facet
    max_slope_idx = np.argmax(slopes, axis=0)
    flow_angle = np.choose(max_slope_idx, flow_angles)
    max_slope = np.max(slopes, axis=0)
    
    return flow_angle, max_slope
```

### Multiple Flow Direction (MFD)

MFD distributes flow to all downslope neighbors:

```python
def mfd_flow_distribution(dem, exponent=1.1):
    """
    Multiple Flow Direction algorithm
    
    Parameters:
    - dem: Digital elevation model
    - exponent: Flow partition exponent (higher = more convergent)
    
    Returns:
    - flow_fractions: Dict of flow fractions to each neighbor
    """
    
    flow_fractions = {}
    
    for i in range(dem.shape[0]):
        for j in range(dem.shape[1]):
            
            # Calculate slope to all neighbors
            slopes = []
            valid_neighbors = []
            
            for di in [-1, 0, 1]:
                for dj in [-1, 0, 1]:
                    if di == 0 and dj == 0:
                        continue
                    
                    ni, nj = i + di, j + dj
                    
                    if 0 <= ni < dem.shape[0] and 0 <= nj < dem.shape[1]:
                        if dem[ni, nj] < dem[i, j]:  # Downslope
                            distance = np.sqrt(di**2 + dj**2) * cell_size
                            slope = (dem[i, j] - dem[ni, nj]) / distance
                            slopes.append(slope ** exponent)
                            valid_neighbors.append((ni, nj))
            
            # Normalize to sum to 1
            if slopes:
                total = sum(slopes)
                fractions = [s / total for s in slopes]
                
                flow_fractions[(i, j)] = dict(zip(valid_neighbors, fractions))
            else:
                flow_fractions[(i, j)] = {}  # Pit or flat
    
    return flow_fractions
```

## Flow Accumulation Calculation

### Recursive Algorithm

```python
def calculate_flow_accumulation(flow_direction, weights=None):
    """
    Calculate flow accumulation from flow direction
    
    Parameters:
    - flow_direction: Flow direction grid (D8 codes or MFD fractions)
    - weights: Optional weight grid (e.g., precipitation)
    
    Returns:
    - accumulation: Flow accumulation grid
    """
    
    if weights is None:
        weights = np.ones_like(flow_direction, dtype=np.float32)
    
    accumulation = weights.copy()
    
    # Find outlets (cells with no upstream neighbors)
    outlets = find_outlets(flow_direction)
    
    # Process from outlets upstream
    processed = np.zeros_like(flow_direction, dtype=bool)
    
    def accumulate_recursive(i, j):
        if processed[i, j]:
            return accumulation[i, j]
        
        # Find upstream cells
        upstream = find_upstream_cells(i, j, flow_direction)
        
        # Accumulate from upstream
        for ui, uj in upstream:
            if not processed[ui, uj]:
                accumulate_recursive(ui, uj)
            accumulation[i, j] += accumulation[ui, uj]
        
        processed[i, j] = True
        return accumulation[i, j]
    
    # Process all cells
    for i in range(flow_direction.shape[0]):
        for j in range(flow_direction.shape[1]):
            accumulate_recursive(i, j)
    
    return accumulation
```

## Slope and Aspect Calculation

### Slope Algorithms

```python
def calculate_slope(dem, method='horn'):
    """
    Calculate slope from DEM
    
    Methods:
    - 'horn': Horn (1981) 3rd-order finite difference
    - 'zevenbergen': Zevenbergen & Thorne (1987)
    - 'average': Simple average method
    """
    
    cell_size = get_cell_size(dem)
    
    if method == 'horn':
        # Horn's method (most accurate)
        dz_dx = ((dem[:-2, 2:] + 2*dem[1:-1, 2:] + dem[2:, 2:]) -
                 (dem[:-2, :-2] + 2*dem[1:-1, :-2] + dem[2:, :-2])) / (8 * cell_size)
        
        dz_dy = ((dem[2:, :-2] + 2*dem[2:, 1:-1] + dem[2:, 2:]) -
                 (dem[:-2, :-2] + 2*dem[:-2, 1:-1] + dem[:-2, 2:])) / (8 * cell_size)
    
    elif method == 'zevenbergen':
        # Zevenbergen & Thorne method
        dz_dx = (dem[1:-1, 2:] - dem[1:-1, :-2]) / (2 * cell_size)
        dz_dy = (dem[2:, 1:-1] - dem[:-2, 1:-1]) / (2 * cell_size)
    
    else:  # average
        # Simple average
        dz_dx = np.diff(dem, axis=1) / cell_size
        dz_dy = np.diff(dem, axis=0) / cell_size
    
    # Calculate slope magnitude
    slope_radians = np.arctan(np.sqrt(dz_dx**2 + dz_dy**2))
    slope_degrees = np.rad2deg(slope_radians)
    
    return slope_degrees
```

### Aspect Calculation

```python
def calculate_aspect(dem):
    """
    Calculate aspect (flow direction azimuth)
    
    Returns:
    - aspect: Degrees clockwise from north (0-360)
    """
    
    # Calculate gradients
    dz_dx = np.gradient(dem, axis=1)
    dz_dy = np.gradient(dem, axis=0)
    
    # Calculate aspect (mathematical convention: CCW from East)
    aspect_math = np.arctan2(dz_dy, -dz_dx)
    
    # Convert to geographic convention (CW from North)
    aspect_geo = np.rad2deg(aspect_math)
    aspect_geo = 90 - aspect_geo
    
    # Normalize to 0-360
    aspect_geo[aspect_geo < 0] += 360
    
    # Flat areas have undefined aspect
    flat_mask = (dz_dx == 0) & (dz_dy == 0)
    aspect_geo[flat_mask] = -1  # Undefined
    
    return aspect_geo
```

## Curvature Analysis

### Profile and Plan Curvature

```python
def calculate_curvature(dem):
    """
    Calculate terrain curvature
    
    Returns:
    - profile_curvature: Curvature in flow direction
    - plan_curvature: Curvature perpendicular to flow
    - mean_curvature: Average curvature
    """
    
    cell_size = get_cell_size(dem)
    
    # Second derivatives
    d2z_dx2 = np.diff(dem, n=2, axis=1) / (cell_size**2)
    d2z_dy2 = np.diff(dem, n=2, axis=0) / (cell_size**2)
    
    # Cross derivative (using central differences)
    dz_dx = np.gradient(dem, cell_size, axis=1)
    dz_dy = np.gradient(dem, cell_size, axis=0)
    d2z_dxdy = np.gradient(dz_dx, cell_size, axis=0)
    
    # First derivatives squared
    p = dz_dx**2
    q = dz_dy**2
    
    # Profile curvature (curvature in direction of maximum slope)
    profile_curv = -(p * d2z_dx2 + 2 * dz_dx * dz_dy * d2z_dxdy + q * d2z_dy2) / \
                   ((p + q) * np.sqrt(1 + p + q)**3)
    
    # Plan curvature (curvature perpendicular to slope direction)
    plan_curv = -(q * d2z_dx2 - 2 * dz_dx * dz_dy * d2z_dxdy + p * d2z_dy2) / \
                ((p + q)**(3/2))
    
    # Mean curvature
    mean_curv = -(d2z_dx2 + d2z_dy2) / 2
    
    return profile_curv, plan_curv, mean_curv
```

### Curvature Classification

```python
def classify_landforms(profile_curv, plan_curv):
    """
    Classify landforms based on curvature
    
    Returns landform classes:
    1. Peak/Ridge (convex-convex)
    2. Ridge (convex-linear)
    3. Shoulder (convex-concave)
    4. Planar (linear-linear)
    5. Pass (linear-concave)
    6. Channel (concave-concave)
    7. Footslope (concave-linear)
    8. Hollow (concave-convex)
    9. Valley/Pit (linear-convex)
    """
    
    # Define thresholds
    threshold = 0.1  # Curvature threshold for classification
    
    # Initialize landform grid
    landforms = np.zeros_like(profile_curv, dtype=np.int8)
    
    # Classify based on curvature combinations
    landforms[(profile_curv > threshold) & (plan_curv > threshold)] = 1  # Peak
    landforms[(profile_curv > threshold) & (np.abs(plan_curv) <= threshold)] = 2  # Ridge
    landforms[(profile_curv > threshold) & (plan_curv < -threshold)] = 3  # Shoulder
    
    landforms[(np.abs(profile_curv) <= threshold) & (np.abs(plan_curv) <= threshold)] = 4  # Planar
    landforms[(np.abs(profile_curv) <= threshold) & (plan_curv < -threshold)] = 5  # Pass
    
    landforms[(profile_curv < -threshold) & (plan_curv < -threshold)] = 6  # Channel
    landforms[(profile_curv < -threshold) & (np.abs(plan_curv) <= threshold)] = 7  # Footslope
    landforms[(profile_curv < -threshold) & (plan_curv > threshold)] = 8  # Hollow
    
    landforms[(np.abs(profile_curv) <= threshold) & (plan_curv > threshold)] = 9  # Valley
    
    return landforms
```

## Topographic Position Index

```python
def calculate_tpi(dem, outer_radius, inner_radius=0):
    """
    Calculate Topographic Position Index
    
    TPI = elevation - mean(neighborhood elevation)
    
    Parameters:
    - dem: Digital elevation model
    - outer_radius: Outer radius of annulus (cells)
    - inner_radius: Inner radius of annulus (cells)
    
    Returns:
    - tpi: Topographic position index
    """
    
    from scipy.ndimage import generic_filter
    
    # Create annulus kernel
    y, x = np.ogrid[-outer_radius:outer_radius+1, -outer_radius:outer_radius+1]
    mask = (x**2 + y**2 <= outer_radius**2) & (x**2 + y**2 > inner_radius**2)
    
    # Calculate neighborhood mean
    def mean_filter(values):
        return np.mean(values[mask.flatten()])
    
    neighborhood_mean = generic_filter(dem, mean_filter, size=2*outer_radius+1)
    
    # Calculate TPI
    tpi = dem - neighborhood_mean
    
    return tpi
```

## Integration with EEMT

### Topographic Controls on Energy

```python
def apply_topographic_controls(solar_radiation, temperature, precipitation, twi):
    """
    Apply topographic modifications to climate variables
    
    Parameters:
    - solar_radiation: Base solar radiation
    - temperature: Base temperature
    - precipitation: Base precipitation  
    - twi: Topographic wetness index
    
    Returns:
    - Modified climate variables
    """
    
    # Solar radiation already includes topographic effects
    solar_modified = solar_radiation
    
    # Temperature modification based on cold air pooling
    # Cold air accumulates in high TWI areas
    cold_pool_effect = np.where(twi > 10, -2.0, 0.0)  # °C cooling
    temp_modified = temperature + cold_pool_effect
    
    # Precipitation enhancement in convergent zones
    # Use MCWI for mass-conservative redistribution
    mcwi = calculate_mcwi(twi, precipitation)
    precip_modified = redistribute_water_mcwi(precipitation, mcwi)
    
    return {
        'solar': solar_modified,
        'temperature': temp_modified,
        'precipitation': precip_modified
    }
```

## Quality Assurance

### Validation Checks

```python
def validate_topographic_indices(dem, twi, flow_acc):
    """
    Quality control for topographic calculations
    """
    
    checks = {}
    
    # Check TWI range
    twi_range = (np.nanmin(twi), np.nanmax(twi))
    checks['twi_range_valid'] = (0 <= twi_range[0]) and (twi_range[1] <= 20)
    
    # Check flow accumulation consistency
    total_cells = dem.size
    max_accumulation = np.nanmax(flow_acc)
    checks['flow_acc_valid'] = max_accumulation <= total_cells
    
    # Check for sinks/pits
    sinks = identify_sinks(dem)
    checks['sink_percentage'] = (np.sum(sinks) / dem.size) * 100
    
    # Check slope calculation
    slopes = calculate_slope(dem)
    checks['max_slope_valid'] = np.nanmax(slopes) <= 90
    
    return checks
```

## References

- Beven, K. J., & Kirkby, M. J. (1979). A physically based, variable contributing area model of basin hydrology. *Hydrological Sciences Bulletin*, 24(1), 43-69.

- Tarboton, D. G. (1997). A new method for the determination of flow directions and upslope areas in grid digital elevation models. *Water Resources Research*, 33(2), 309-319.

- Quinn, P., et al. (1991). The prediction of hillslope flow paths for distributed hydrological modelling using digital terrain models. *Hydrological Processes*, 5(1), 59-79.

---

*Next: [EEMT Calculations →](eemt-calculations.md)*