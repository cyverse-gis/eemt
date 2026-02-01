# EEMT Jupyter Notebooks Plan

## Overview

This plan outlines a comprehensive set of Jupyter notebooks designed to demonstrate, teach, and enable EEMT (Effective Energy and Mass Transfer) calculations using the conda environment specified in `environment.yml`. The notebooks will cover all aspects of the scientific background, data access, GRASS GIS workflows, and calculation methods documented in the `docs/` directory.

## Target Audience

- **Graduate students** in earth sciences, ecology, and geomorphology
- **Researchers** working on Critical Zone science and landscape evolution  
- **Practitioners** implementing energy-based approaches to ecosystem analysis
- **Software developers** contributing to geospatial modeling tools

## Notebook Categories

### 1. Scientific Background (`01_background/`)

#### 1.1 Critical Zone Thermodynamics (`01_critical_zone_thermodynamics.ipynb`)
**Objective**: Introduce the thermodynamic foundation of Critical Zone processes

**Content**:
- Energy balance principles and open system thermodynamics
- Mathematical framework for energy flux calculations
- Interactive visualizations of energy components (E_BIO, E_PPT, E_ET)
- Threshold behavior demonstration (~70 MJ/m²/yr transition)
- Case studies from different climate zones

**Key Features**:
- Interactive energy balance diagrams using Plotly
- Thermodynamic equations with SymPy symbolic math
- Climate gradient analysis with real data
- Energy threshold identification exercises

#### 1.2 Solar Radiation and Topography (`02_solar_topography.ipynb`)
**Objective**: Demonstrate how topography modifies solar energy input

**Content**:
- Solar geometry and radiation calculations
- Slope, aspect, and shading effects on radiation
- Seasonal and daily variation patterns
- Topographic solar modeling with sample DEMs

**Key Features**:
- 3D terrain visualization with PyVista
- Interactive solar angle calculations
- Hillshade and solar radiation mapping
- Comparison of flat vs. topographic radiation

#### 1.3 EEMT Mathematical Framework (`03_eemt_equations.ipynb`)
**Objective**: Deep dive into EEMT calculation mathematics

**Content**:
- Step-by-step derivation of EEMT components
- Energy conservation and entropy production
- Statistical relationships and power laws
- Validation against field measurements

**Key Features**:
- Symbolic equation derivations with SymPy
- Parameter sensitivity analysis
- Power law fitting and visualization
- Field data comparison plots

### 2. Data Sources and Access (`02_data_sources/`)

#### 2.1 Elevation Data Access (`01_elevation_data.ipynb`)
**Objective**: Demonstrate accessing public elevation datasets

**Content**:
- USGS 3DEP API access and download
- OpenTopography global DEM access
- LiDAR point cloud processing with PDAL
- DEM quality assessment and validation
- Coordinate system handling and reprojection

**Key Features**:
- API-based data download functions
- Interactive map-based area selection with Folium
- Elevation profile visualization
- DEM comparison and quality metrics

#### 2.2 Climate Data Integration (`02_climate_data.ipynb`)
**Objective**: Access and process DAYMET and other climate datasets

**Content**:
- DAYMET v4 API access and spatial subsetting
- PRISM monthly climate normals
- GridMET daily meteorological data
- Climate data preprocessing and quality control
- Temporal trend analysis

**Key Features**:
- Automated climate data download
- Time series visualization with Plotly
- Climate anomaly detection
- Spatial interpolation techniques

#### 2.3 Satellite and Vegetation Data (`03_satellite_data.ipynb`)
**Objective**: Process vegetation indices and remote sensing data

**Content**:
- Landsat NDVI calculation and time series
- MODIS LAI product access
- Google Earth Engine integration
- Vegetation phenology analysis

**Key Features**:
- Cloud-masked satellite imagery processing
- Vegetation index time series analysis
- Phenology curve fitting
- Multi-sensor data fusion

### 3. GRASS GIS Workflows (`03_grass_workflows/`)

#### 3.1 GRASS Environment Setup (`01_grass_setup.ipynb`)
**Objective**: Configure GRASS GIS for EEMT calculations

**Content**:
- GRASS location and mapset creation
- DEM import and region setting
- Basic terrain analysis (slope, aspect, hillshade)
- GRASS Python integration with grass-session

**Key Features**:
- Automated GRASS environment setup
- Interactive region definition
- Terrain visualization in notebook
- Python-GRASS integration examples

#### 3.2 Solar Radiation Modeling (`02_solar_modeling.ipynb`)
**Objective**: Implement r.sun for solar radiation calculations

**Content**:
- r.sun.mp configuration and execution
- Daily and annual solar modeling
- Atmospheric parameter effects (Linke, albedo)
- Solar radiation validation and analysis

**Key Features**:
- Parallel r.sun execution examples
- Solar radiation mapping and analysis
- Parameter sensitivity exploration
- Performance benchmarking

#### 3.3 Hydrological Analysis (`03_hydrology.ipynb`)
**Objective**: Calculate flow accumulation and wetness indices

**Content**:
- Watershed delineation with r.watershed
- Topographic wetness index (TWI) calculation
- Mass-conservative wetness index (MCWI)
- Flow path visualization

**Key Features**:
- 3D watershed visualization
- Stream network extraction
- Wetness index interpretation
- Flow accumulation analysis

### 4. EEMT Calculation Methods (`04_calculation_methods/`)

#### 4.1 Traditional EEMT (`01_traditional_eemt.ipynb`)
**Objective**: Implement basic climate-based EEMT approach

**Content**:
- Temperature and precipitation-based NPP estimation
- Potential evapotranspiration calculations
- Effective precipitation determination
- Traditional EEMT mapping

**Key Features**:
- Step-by-step EEMT calculation
- Climate variable relationships
- NPP estimation methods
- Results validation and interpretation

#### 4.2 Topographic EEMT (`02_topographic_eemt.ipynb`)
**Objective**: Advanced EEMT with topographic controls

**Content**:
- Solar radiation integration
- Topographic temperature modification
- Water redistribution with MCWI
- Enhanced NPP estimation with terrain effects

**Key Features**:
- Full workflow automation
- Topographic effect quantification
- Spatial pattern analysis
- Method comparison visualization

#### 4.3 Vegetation EEMT (`03_vegetation_eemt.ipynb`)
**Objective**: Complete EEMT with vegetation structure

**Content**:
- LAI calculation from NDVI
- Canopy height integration
- Surface resistance calculations
- Penman-Monteith evapotranspiration

**Key Features**:
- Multi-sensor vegetation analysis
- Complete energy balance modeling
- Vegetation-energy coupling
- High-resolution EEMT mapping

#### 4.4 EEMT Methods Comparison (`04_methods_comparison.ipynb`)
**Objective**: Compare all three EEMT approaches

**Content**:
- Side-by-side method comparison
- Difference mapping and analysis
- Statistical validation against field data
- Method selection guidelines

**Key Features**:
- Comprehensive results comparison
- Validation metrics calculation
- Method performance analysis
- Decision support visualization

### 5. Advanced Applications (`05_applications/`)

#### 5.1 Critical Zone Observatory Analysis (`01_czo_analysis.ipynb`)
**Objective**: Apply EEMT to Critical Zone Observatory sites

**Content**:
- CZO site data integration
- EEMT calculation across climate gradients
- Soil development rate prediction
- Ecosystem service quantification

**Key Features**:
- Multi-site comparative analysis
- Gradient analysis visualization
- Predictive model development
- Ecosystem service mapping

#### 5.2 Climate Change Impacts (`02_climate_impacts.ipynb`)
**Objective**: Assess EEMT response to climate change

**Content**:
- Future climate scenario processing
- EEMT projection calculations
- Ecosystem transition analysis
- Vulnerability assessment

**Key Features**:
- Climate scenario integration
- Future projection visualization
- Ecosystem transition mapping
- Uncertainty quantification

#### 5.3 Large-Scale Continental Analysis (`03_continental_analysis.ipynb`)
**Objective**: Scale EEMT to regional and continental extents

**Content**:
- Tile-based processing for large areas
- Parallel computation strategies
- Continental-scale EEMT patterns
- Biogeographic boundary identification

**Key Features**:
- Scalable processing workflows
- Continental visualization
- Pattern analysis techniques
- Performance optimization

## Technical Implementation Strategy

### Conda Environment Integration

All notebooks will use the `eemt-gis` conda environment specified in `environment.yml`:

```python
# Standard environment activation in each notebook
import os
import sys

# Ensure we're using the correct environment
if 'CONDA_DEFAULT_ENV' not in os.environ or os.environ['CONDA_DEFAULT_ENV'] != 'eemt-gis':
    print("Warning: Please activate 'eemt-gis' conda environment")
    print("Run: conda activate eemt-gis")

# Core scientific stack
import numpy as np
import pandas as pd
import xarray as xr
import rasterio
import geopandas as gpd

# Visualization
import matplotlib.pyplot as plt
import plotly.express as px
import plotly.graph_objects as go
import folium
import contextily as ctx

# GRASS GIS integration
import grass.session as gs
from grass.exceptions import CalledModuleError

# Geospatial analysis
from scipy import ndimage, stats
from scikit-image import morphology
from shapely.geometry import Point, Polygon
```

### Notebook Structure Template

Each notebook will follow a consistent structure:

1. **Environment Setup** (5 minutes)
   - Package imports and environment verification
   - Data directory setup
   - Helper function definitions

2. **Learning Objectives** (2 minutes)
   - Clear statement of notebook goals
   - Expected outcomes and skills

3. **Theoretical Background** (10 minutes)
   - Scientific concepts and equations
   - Visual explanations with diagrams

4. **Data Preparation** (10 minutes)
   - Sample data download/access
   - Quality control and validation
   - Preprocessing steps

5. **Implementation** (20 minutes)
   - Step-by-step calculation workflow
   - Interactive parameter exploration
   - Intermediate result visualization

6. **Results Analysis** (10 minutes)
   - Output interpretation
   - Statistical analysis
   - Comparison with literature

7. **Exercises and Extensions** (5 minutes)
   - Student practice problems
   - Advanced exploration suggestions
   - Real-world application ideas

### Data Management Strategy

#### Sample Datasets

Each notebook category will include curated sample datasets:

- **Small test datasets** (< 10 MB): Included directly in repository
- **Medium datasets** (10-100 MB): Downloaded programmatically
- **Large datasets** (> 100 MB): Cloud-based access with subset examples

#### Data Organization

```
notebooks/
├── data/
│   ├── elevation/           # Sample DEMs
│   │   ├── small_dem.tif    # 1 km² test area
│   │   └── medium_dem.tif   # 100 km² regional area
│   ├── climate/             # Sample climate data
│   │   ├── daymet_sample/   # 5-year DAYMET subset
│   │   └── prism_sample/    # Monthly normals
│   ├── validation/          # Field validation data
│   │   ├── soil_depth.csv   # Point measurements
│   │   └── biomass.csv      # Vegetation biomass
│   └── outputs/             # Generated results
├── utilities/               # Shared functions
│   ├── data_access.py       # Download utilities
│   ├── eemt_calculations.py # Core EEMT functions
│   ├── visualization.py     # Plotting utilities
│   └── grass_interface.py   # GRASS integration
└── [notebook directories]/
```

### Interactive Features

#### Widgets and User Interface

```python
import ipywidgets as widgets
from ipywidgets import interact, FloatSlider, Dropdown

# Example: Interactive parameter exploration
@interact(
    linke_value=FloatSlider(min=1.0, max=8.0, step=0.5, value=3.0),
    albedo_value=FloatSlider(min=0.0, max=1.0, step=0.05, value=0.2),
    elevation=FloatSlider(min=0, max=4000, step=100, value=1500)
)
def explore_solar_radiation(linke_value, albedo_value, elevation):
    """Interactive solar radiation calculation"""
    # Calculate and visualize solar radiation
    result = calculate_solar(linke_value, albedo_value, elevation)
    display_solar_plot(result)
```

#### 3D Visualization

```python
import pyvista as pv

# Example: 3D terrain and solar radiation visualization
def create_3d_terrain_plot(dem_array, solar_array):
    """Create 3D terrain plot with solar radiation overlay"""
    
    # Create PyVista grid
    grid = pv.UniformGrid(dem_array.shape)
    grid["elevation"] = dem_array.flatten()
    grid["solar_radiation"] = solar_array.flatten()
    
    # Create 3D plot
    warped = grid.warp_by_scalar("elevation", factor=2.0)
    
    plotter = pv.Plotter(notebook=True)
    plotter.add_mesh(warped, scalars="solar_radiation", 
                     cmap="viridis", show_edges=False)
    plotter.show()
```

#### Interactive Maps

```python
import folium
from folium import plugins

def create_eemt_map(eemt_array, bounds, center_lat, center_lon):
    """Create interactive EEMT map with folium"""
    
    # Create base map
    m = folium.Map(location=[center_lat, center_lon], zoom_start=10)
    
    # Add EEMT raster overlay
    folium.raster_layers.ImageOverlay(
        image=eemt_array,
        bounds=bounds,
        opacity=0.7,
        colormap=lambda x: (0, 0, x, 1),
        mercator_project=True
    ).add_to(m)
    
    # Add colorbar
    colormap = cm.linear.viridis.scale(
        eemt_array.min(), eemt_array.max()
    ).to_step(10)
    colormap.caption = 'EEMT (MJ/m²/yr)'
    colormap.add_to(m)
    
    return m
```

## Assessment and Learning Outcomes

### Formative Assessment

Each notebook includes built-in assessments:

1. **Code completion exercises** - Fill in missing code segments
2. **Parameter exploration** - Interactive parameter testing
3. **Interpretation questions** - Analysis of results and patterns
4. **Method comparison** - Compare different approaches

### Summative Assessment Options

For educational settings:

1. **Project assignments** - Apply EEMT to student-selected study areas
2. **Method validation** - Compare results with published studies
3. **Scale analysis** - Investigate scale effects on EEMT patterns
4. **Innovation challenges** - Develop new EEMT applications

### Learning Outcome Verification

Students completing the notebook series will demonstrate:

1. **Conceptual understanding** - Critical Zone energy principles
2. **Technical proficiency** - Python geospatial analysis skills
3. **Method application** - EEMT calculation implementation
4. **Scientific interpretation** - Results analysis and validation
5. **Research preparation** - Independent project development

## Distribution and Maintenance

### Version Control and Updates

- **Git-based versioning** with semantic release numbers
- **Automated testing** for notebook execution
- **Continuous integration** for dependency validation
- **Regular updates** aligned with package releases

### Documentation Integration

- **Cross-linking** with main documentation
- **API reference** integration
- **Citation management** for scientific references
- **Example data provenance** and licensing

### Community Contributions

- **Template notebooks** for new applications
- **Contribution guidelines** for notebook development
- **Peer review process** for quality assurance
- **User feedback integration** and iterative improvement

## Technical Validation

### Automated Testing

```python
import pytest
import nbformat
from nbconvert.preprocessors import ExecutePreprocessor

def test_notebook_execution(notebook_path):
    """Test that notebook executes without errors"""
    
    with open(notebook_path) as f:
        nb = nbformat.read(f, as_version=4)
    
    ep = ExecutePreprocessor(timeout=600, kernel_name='python3')
    
    try:
        ep.preprocess(nb, {'metadata': {'path': './'}})
    except Exception as e:
        pytest.fail(f"Notebook {notebook_path} failed to execute: {e}")
```

### Performance Benchmarking

```python
import time
import psutil

def benchmark_notebook_performance(notebook_function):
    """Benchmark notebook calculation performance"""
    
    start_time = time.time()
    start_memory = psutil.virtual_memory().used
    
    result = notebook_function()
    
    end_time = time.time()
    end_memory = psutil.virtual_memory().used
    
    return {
        'execution_time': end_time - start_time,
        'memory_used': (end_memory - start_memory) / 1024**2,  # MB
        'result': result
    }
```

## Implementation Timeline

### Phase 1: Core Notebooks (Weeks 1-4)
- Scientific background notebooks (3 notebooks)
- Data access fundamentals (2 notebooks)  
- Basic GRASS workflows (2 notebooks)

### Phase 2: Calculation Methods (Weeks 5-8)
- Traditional EEMT implementation
- Topographic EEMT with solar integration
- Vegetation EEMT with remote sensing
- Methods comparison and validation

### Phase 3: Advanced Applications (Weeks 9-12)
- Multi-site analysis notebooks
- Climate change impact assessment
- Continental-scale processing
- Performance optimization examples

### Phase 4: Testing and Documentation (Weeks 13-14)
- Comprehensive testing suite
- Performance benchmarking
- Documentation integration
- Community review and feedback

## Success Metrics

### Technical Metrics
- **Execution success rate** > 95% across all environments
- **Performance benchmarks** < 10 minutes per core notebook
- **Memory efficiency** < 4GB RAM for standard examples
- **Dependency compatibility** across major OS platforms

### Educational Metrics
- **User engagement** tracking through analytics
- **Community contributions** (issues, PRs, discussions)
- **Citation impact** in educational and research contexts
- **Adoption rate** in academic courses

### Scientific Impact
- **Method validation** against published studies
- **Novel applications** developed by users
- **Publication contributions** from notebook-based research
- **Community feedback** and improvement suggestions

This comprehensive notebook suite will establish EEMT as an accessible and powerful framework for Critical Zone science education and research, providing hands-on experience with cutting-edge geospatial modeling techniques while building practical skills in Python scientific computing.