---
title: EEMT Calculation Algorithms
description: Core algorithms for calculating Effective Energy and Mass Transfer components
---

# EEMT Calculation Algorithms

## Overview

The Effective Energy and Mass Transfer (EEMT) framework quantifies the energy available to drive Critical Zone processes. EEMT combines biological energy storage through primary production (E<sub>BIO</sub>) with precipitation-delivered thermal energy (E<sub>PPT</sub>) to predict landscape evolution, soil formation, and ecosystem function.

## Core EEMT Equation

### Fundamental Formula

$$\text{EEMT} = E_{BIO} + E_{PPT} \quad \text{[MJ m}^{-2} \text{ yr}^{-1}\text{]}$$

Where:
- **E<sub>BIO</sub>** = Biological energy from net primary production
- **E<sub>PPT</sub>** = Thermal energy from effective precipitation

This represents the total energy flux available for:
- Chemical weathering reactions
- Soil formation processes
- Biological activity
- Carbon sequestration
- Nutrient cycling

## Biological Energy Component (E<sub>BIO</sub>)

### Mathematical Formulation

$$E_{BIO} = \text{NPP} \times h_{BIO}$$

Where:
- **NPP** = Net Primary Production [kg m⁻² yr⁻¹]
- **h<sub>BIO</sub>** = Specific enthalpy of biomass (22 × 10⁶ J kg⁻¹)

### NPP Estimation Methods

#### 1. Climate-Based NPP (Lieth Model)

```python
def calculate_npp_lieth(mean_annual_temp, annual_precip):
    """
    Lieth (1975) Miami model for NPP estimation
    
    Parameters:
    - mean_annual_temp: Mean annual temperature [°C]
    - annual_precip: Annual precipitation [mm]
    
    Returns:
    - npp: Net primary production [g m⁻² yr⁻¹]
    """
    
    # Temperature-limited NPP
    npp_temp = 3000 / (1 + np.exp(1.315 - 0.119 * mean_annual_temp))
    
    # Precipitation-limited NPP
    npp_precip = 3000 * (1 - np.exp(-0.000664 * annual_precip))
    
    # Take minimum (Liebig's law)
    npp = np.minimum(npp_temp, npp_precip)
    
    return npp
```

#### 2. MODIS NPP Integration

```python
def integrate_modis_npp(modis_npp_file, scale_factor=0.0001):
    """
    Use MODIS NPP product (MOD17A3)
    
    Parameters:
    - modis_npp_file: Path to MODIS NPP data
    - scale_factor: MODIS scale factor
    
    Returns:
    - annual_npp: Annual NPP [kg m⁻² yr⁻¹]
    """
    
    import rasterio
    
    with rasterio.open(modis_npp_file) as src:
        npp_raw = src.read(1)
        
    # Apply scale factor and convert units
    # MODIS NPP is in kg C m⁻² yr⁻¹
    # Convert to total biomass (assume 45% carbon content)
    annual_npp = npp_raw * scale_factor / 0.45
    
    # Quality control
    annual_npp[annual_npp < 0] = 0
    annual_npp[annual_npp > 5] = 5  # Max ~5 kg m⁻² yr⁻¹
    
    return annual_npp
```

#### 3. Topographic NPP Model

```python
def calculate_npp_topographic(elevation, northness, base_npp=0.5):
    """
    Whittaker & Niering (1975) topographic NPP model
    
    NPP = α × elevation + β × northness + γ
    
    Parameters:
    - elevation: Elevation [m]
    - northness: Topographic northness index [-1 to 1]
    - base_npp: Baseline NPP [kg m⁻² yr⁻¹]
    
    Returns:
    - npp: Topographically-adjusted NPP [kg m⁻² yr⁻¹]
    """
    
    # Empirical coefficients (site-specific calibration recommended)
    alpha = 0.00039  # kg m⁻² yr⁻¹ per meter elevation
    beta = 0.346     # kg m⁻² yr⁻¹ per unit northness
    gamma = -0.187   # kg m⁻² yr⁻¹ baseline adjustment
    
    # Calculate NPP
    npp = alpha * elevation + beta * northness + gamma + base_npp
    
    # Constrain to reasonable range
    npp = np.maximum(0.1, np.minimum(5.0, npp))
    
    return npp
```

### E<sub>BIO</sub> Calculation

```python
def calculate_e_bio(npp, time_integration='annual'):
    """
    Calculate biological energy component
    
    Parameters:
    - npp: Net primary production [kg m⁻² yr⁻¹]
    - time_integration: 'annual' or 'monthly'
    
    Returns:
    - e_bio: Biological energy flux [MJ m⁻² yr⁻¹]
    """
    
    # Specific enthalpy of biomass
    h_bio = 22e6  # J/kg (from bomb calorimetry studies)
    
    if time_integration == 'annual':
        # Direct calculation
        e_bio = npp * h_bio / 1e6  # Convert J to MJ
        
    elif time_integration == 'monthly':
        # Account for seasonal variation
        monthly_fraction = get_phenology_fraction()  # 12 values summing to 1
        e_bio_monthly = []
        
        for month in range(12):
            npp_month = npp * monthly_fraction[month]
            e_bio_month = npp_month * h_bio / 1e6
            e_bio_monthly.append(e_bio_month)
        
        e_bio = np.sum(e_bio_monthly, axis=0)
    
    return e_bio
```

## Precipitation Energy Component (E<sub>PPT</sub>)

### Mathematical Formulation

$$E_{PPT} = \rho_w \times P_{eff} \times c_w \times \Delta T$$

Where:
- **ρ<sub>w</sub>** = Density of water (1000 kg m⁻³)
- **P<sub>eff</sub>** = Effective precipitation [m yr⁻¹]
- **c<sub>w</sub>** = Specific heat of water (4180 J kg⁻¹ K⁻¹)
- **ΔT** = Temperature above freezing [K]

### Effective Precipitation Calculation

```python
def calculate_effective_precipitation(precipitation, pet, aet=None):
    """
    Calculate effective precipitation (available for subsurface processes)
    
    Parameters:
    - precipitation: Total precipitation [mm]
    - pet: Potential evapotranspiration [mm]
    - aet: Actual evapotranspiration [mm] (optional)
    
    Returns:
    - p_eff: Effective precipitation [mm]
    """
    
    if aet is not None:
        # Use actual ET if available
        p_eff = precipitation - aet
    else:
        # Estimate using Budyko curve
        aridity_index = pet / np.maximum(precipitation, 1)
        
        # Fu's equation (Fu, 1981)
        omega = 2.6  # Shape parameter
        evap_ratio = 1 + aridity_index - (1 + aridity_index**omega)**(1/omega)
        aet = precipitation * evap_ratio
        
        p_eff = precipitation - aet
    
    # Ensure non-negative
    p_eff = np.maximum(0, p_eff)
    
    return p_eff
```

### Temperature Delta Calculation

```python
def calculate_temperature_delta(temperature, phase='liquid'):
    """
    Calculate temperature difference from reference
    
    Parameters:
    - temperature: Temperature [°C]
    - phase: 'liquid' or 'solid' (snow/ice)
    
    Returns:
    - delta_t: Temperature above reference [K]
    """
    
    if phase == 'liquid':
        # Reference is freezing point
        reference_temp = 0.0  # °C
        delta_t = np.maximum(0, temperature - reference_temp)
        
    elif phase == 'solid':
        # For snow, use temperature below freezing
        reference_temp = 0.0  # °C
        delta_t = np.maximum(0, reference_temp - temperature)
        # Account for latent heat of fusion
        delta_t = delta_t * 0.1  # Reduced factor for snow
    
    return delta_t
```

### E<sub>PPT</sub> Calculation

```python
def calculate_e_ppt(precipitation, temperature, et, method='budyko'):
    """
    Calculate precipitation energy component
    
    Parameters:
    - precipitation: Precipitation [mm yr⁻¹]
    - temperature: Mean temperature [°C]
    - et: Evapotranspiration [mm yr⁻¹]
    - method: 'budyko' or 'penman-monteith'
    
    Returns:
    - e_ppt: Precipitation energy [MJ m⁻² yr⁻¹]
    """
    
    # Calculate effective precipitation
    if method == 'budyko':
        p_eff = calculate_effective_precipitation(precipitation, et)
    else:  # penman-monteith
        p_eff = precipitation - et  # ET already calculated
    
    # Convert mm to m
    p_eff_m = p_eff / 1000
    
    # Water properties
    rho_water = 1000  # kg/m³
    c_water = 4180    # J/(kg·K)
    
    # Calculate temperature delta
    delta_t = calculate_temperature_delta(temperature)
    
    # Calculate energy flux
    # Mass flux: kg/(m²·yr) = rho * depth
    mass_flux = rho_water * p_eff_m
    
    # Energy: J/(m²·yr) = mass_flux * c_water * delta_t
    e_ppt_j = mass_flux * c_water * delta_t
    
    # Convert to MJ
    e_ppt = e_ppt_j / 1e6
    
    return e_ppt
```

## Integrated EEMT Calculation

### Complete EEMT Workflow

```python
def calculate_eemt_complete(dem, climate_data, vegetation_data=None, 
                           method='topographic'):
    """
    Complete EEMT calculation with all components
    
    Parameters:
    - dem: Digital elevation model
    - climate_data: Dict with temperature, precipitation, radiation
    - vegetation_data: Optional vegetation inputs (LAI, NDVI, etc.)
    - method: 'traditional', 'topographic', or 'vegetation'
    
    Returns:
    - eemt_components: Dict with EEMT, E_BIO, E_PPT
    """
    
    # Extract climate variables
    temp = climate_data['temperature']
    precip = climate_data['precipitation']
    
    # Calculate topographic indices
    slope = calculate_slope(dem)
    aspect = calculate_aspect(dem)
    twi = calculate_twi(dem)
    mcwi = calculate_mcwi(twi, precip)
    
    # Method-specific calculations
    if method == 'traditional':
        # Simple climate-based approach
        npp = calculate_npp_lieth(temp.mean(), precip.sum())
        pet = calculate_pet_hamon(temp, daylight_hours=12)
        p_eff = calculate_effective_precipitation(precip, pet)
        
    elif method == 'topographic':
        # Include topographic controls
        northness = calculate_northness(aspect, slope)
        npp = calculate_npp_topographic(dem, northness)
        
        # Redistribute precipitation
        p_redistributed = redistribute_water_mcwi(precip, mcwi)
        pet = calculate_pet_priestley_taylor(climate_data['radiation'], temp)
        p_eff = calculate_effective_precipitation(p_redistributed, pet)
        
    elif method == 'vegetation':
        # Full vegetation integration
        if vegetation_data and 'lai' in vegetation_data:
            lai = vegetation_data['lai']
        else:
            lai = estimate_lai_from_climate(temp, precip)
        
        # Vegetation-modified NPP
        canopy_height = lai * 2.5  # Simple approximation
        npp = calculate_npp_vegetation(canopy_height)
        
        # Vegetation-modified ET
        aet = calculate_aet_penman_monteith(temp, climate_data['humidity'], 
                                           climate_data['wind'], 
                                           climate_data['radiation'], lai)
        p_eff = precip - aet
    
    # Calculate energy components
    e_bio = calculate_e_bio(npp)
    e_ppt = calculate_e_ppt(precip, temp, p_eff)
    
    # Total EEMT
    eemt = e_bio + e_ppt
    
    # Apply quality control
    eemt = apply_eemt_limits(eemt)
    
    return {
        'eemt': eemt,
        'e_bio': e_bio,
        'e_ppt': e_ppt,
        'npp': npp,
        'p_eff': p_eff,
        'twi': twi,
        'mcwi': mcwi
    }
```

## EEMT Thresholds and Regimes

### Energy-Limited vs Water-Limited Systems

```python
def classify_eemt_regime(eemt, precipitation, temperature):
    """
    Classify landscape into EEMT regimes
    
    Based on Rasmussen et al. (2014) thresholds
    """
    
    # Key threshold
    eemt_threshold = 70  # MJ m⁻² yr⁻¹
    
    # Additional criteria
    aridity = calculate_aridity_index(precipitation, temperature)
    
    regime = np.empty_like(eemt, dtype='U20')
    
    # Water-limited (below threshold)
    water_limited = (eemt < eemt_threshold) | (aridity > 1.5)
    regime[water_limited] = 'water_limited'
    
    # Energy-limited (above threshold)
    energy_limited = (eemt >= eemt_threshold) & (aridity < 0.7)
    regime[energy_limited] = 'energy_limited'
    
    # Transitional
    transitional = ~(water_limited | energy_limited)
    regime[transitional] = 'transitional'
    
    # Sub-classifications
    regime[(regime == 'water_limited') & (eemt < 10)] = 'hyperarid'
    regime[(regime == 'energy_limited') & (eemt > 150)] = 'humid_tropical'
    
    return regime
```

### EEMT-Driven Process Rates

```python
def predict_process_rates(eemt):
    """
    Predict Critical Zone process rates from EEMT
    
    Returns:
    - Dictionary of predicted rates
    """
    
    rates = {}
    
    # Soil production rate (exponential model)
    # Based on Pelletier & Rasmussen (2009)
    P0 = 0.05  # mm/yr maximum rate
    k = 0.02   # Decay constant
    rates['soil_production'] = P0 * np.exp(-k * eemt)
    
    # Chemical denudation rate (linear model)
    # Based on Rasmussen et al. (2011)
    rates['chemical_denudation'] = 0.15 * eemt + 5  # t km⁻² yr⁻¹
    
    # Physical erosion rate (power law)
    # Inverse relationship in high EEMT
    if isinstance(eemt, np.ndarray):
        rates['physical_erosion'] = np.where(
            eemt < 70,
            100 * eemt**(-0.5),  # High erosion in dry areas
            20 * eemt**(-0.8)    # Low erosion in wet areas
        )
    else:
        if eemt < 70:
            rates['physical_erosion'] = 100 * eemt**(-0.5)
        else:
            rates['physical_erosion'] = 20 * eemt**(-0.8)
    
    # Biomass accumulation (logistic model)
    K = 50  # kg/m² carrying capacity
    r = 0.05  # Growth rate
    rates['biomass'] = K / (1 + np.exp(-r * (eemt - 70)))
    
    return rates
```

## Uncertainty Quantification

### Monte Carlo Uncertainty Analysis

```python
def eemt_uncertainty_analysis(climate_data, dem, n_simulations=1000):
    """
    Quantify EEMT uncertainty through Monte Carlo simulation
    
    Parameters:
    - climate_data: Base climate data
    - dem: Digital elevation model
    - n_simulations: Number of Monte Carlo runs
    
    Returns:
    - uncertainty_stats: Statistical measures of uncertainty
    """
    
    eemt_simulations = []
    
    for i in range(n_simulations):
        # Perturb input parameters
        temp_perturbed = climate_data['temperature'] + np.random.normal(0, 1)
        precip_perturbed = climate_data['precipitation'] * np.random.lognormal(0, 0.1)
        
        # Vary NPP model parameters
        npp_scaling = np.random.uniform(0.8, 1.2)
        
        # Vary ET model parameters
        et_scaling = np.random.uniform(0.9, 1.1)
        
        # Calculate EEMT with perturbed inputs
        climate_perturbed = {
            'temperature': temp_perturbed,
            'precipitation': precip_perturbed,
            'radiation': climate_data['radiation']
        }
        
        eemt_result = calculate_eemt_complete(dem, climate_perturbed)
        eemt_simulations.append(eemt_result['eemt'])
    
    # Calculate statistics
    eemt_stack = np.stack(eemt_simulations, axis=0)
    
    uncertainty_stats = {
        'mean': np.mean(eemt_stack, axis=0),
        'std': np.std(eemt_stack, axis=0),
        'cv': np.std(eemt_stack, axis=0) / np.mean(eemt_stack, axis=0),
        'percentile_5': np.percentile(eemt_stack, 5, axis=0),
        'percentile_95': np.percentile(eemt_stack, 95, axis=0),
        'confidence_interval': np.percentile(eemt_stack, [2.5, 97.5], axis=0)
    }
    
    return uncertainty_stats
```

### Sensitivity Analysis

```python
def eemt_sensitivity_analysis(base_inputs, parameter_ranges):
    """
    Perform sensitivity analysis on EEMT parameters
    
    Parameters:
    - base_inputs: Baseline input values
    - parameter_ranges: Dict of parameter ranges to test
    
    Returns:
    - sensitivity: Parameter sensitivity indices
    """
    
    sensitivity = {}
    base_eemt = calculate_eemt_complete(**base_inputs)['eemt']
    
    for param, (low, high) in parameter_ranges.items():
        # Test low value
        inputs_low = base_inputs.copy()
        inputs_low[param] = low
        eemt_low = calculate_eemt_complete(**inputs_low)['eemt']
        
        # Test high value
        inputs_high = base_inputs.copy()
        inputs_high[param] = high
        eemt_high = calculate_eemt_complete(**inputs_high)['eemt']
        
        # Calculate sensitivity index
        delta_param = (high - low) / base_inputs[param]
        delta_eemt = (eemt_high - eemt_low) / base_eemt
        
        sensitivity[param] = delta_eemt / delta_param
    
    return sensitivity
```

## Quality Control

### Physical Constraints

```python
def apply_eemt_limits(eemt):
    """
    Apply physical constraints to EEMT values
    
    Parameters:
    - eemt: Calculated EEMT values
    
    Returns:
    - eemt_constrained: Physically reasonable EEMT
    """
    
    # Physical limits based on global observations
    MIN_EEMT = 0.1    # Minimum in extreme deserts
    MAX_EEMT = 500    # Maximum in tropical rainforests
    
    # Apply constraints
    eemt_constrained = np.clip(eemt, MIN_EEMT, MAX_EEMT)
    
    # Check for anomalies
    if isinstance(eemt, np.ndarray):
        # Identify outliers (> 3 std from mean)
        mean = np.nanmean(eemt_constrained)
        std = np.nanstd(eemt_constrained)
        outliers = np.abs(eemt_constrained - mean) > 3 * std
        
        if np.any(outliers):
            print(f"Warning: {np.sum(outliers)} outlier pixels detected")
    
    return eemt_constrained
```

### Validation Metrics

```python
def validate_eemt_results(eemt_calculated, validation_data):
    """
    Validate EEMT against field observations
    
    Parameters:
    - eemt_calculated: Calculated EEMT values
    - validation_data: Field measurements or reference data
    
    Returns:
    - metrics: Validation metrics
    """
    
    from sklearn.metrics import mean_squared_error, r2_score
    
    # Ensure same shape
    if eemt_calculated.shape != validation_data.shape:
        validation_data = resample_to_match(validation_data, eemt_calculated)
    
    # Remove NaN values
    mask = ~(np.isnan(eemt_calculated) | np.isnan(validation_data))
    calc_valid = eemt_calculated[mask]
    obs_valid = validation_data[mask]
    
    # Calculate metrics
    metrics = {
        'rmse': np.sqrt(mean_squared_error(obs_valid, calc_valid)),
        'mae': np.mean(np.abs(obs_valid - calc_valid)),
        'r2': r2_score(obs_valid, calc_valid),
        'bias': np.mean(calc_valid - obs_valid),
        'correlation': np.corrcoef(obs_valid, calc_valid)[0, 1],
        'n_samples': len(calc_valid)
    }
    
    # Relative metrics
    metrics['relative_rmse'] = metrics['rmse'] / np.mean(obs_valid)
    metrics['relative_bias'] = metrics['bias'] / np.mean(obs_valid)
    
    return metrics
```

## References

- Rasmussen, C., et al. (2014). Quantifying topographic and vegetation effects on the transfer of energy and mass to the Critical Zone. *Vadose Zone Journal*, 14(11).

- Pelletier, J. D., & Rasmussen, C. (2009). Geomorphically based predictive mapping of soil thickness in upland watersheds. *Water Resources Research*, 45(9).

- Lieth, H. (1975). Modeling the primary productivity of the world. In *Primary productivity of the biosphere* (pp. 237-263). Springer.

- Fu, B. P. (1981). On the calculation of the evaporation from land surface. *Scientia Atmospherica Sinica*, 5(1), 23-31.

---

*Next: [Practical Workflows →](../workflows/quick-start.md)*