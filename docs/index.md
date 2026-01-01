# Effective Energy and Mass Transfer (EEMT)

!!! note "Latest Updates"
    **2026-01-01**: Python 3 migration complete, Docker infrastructure modernized, UI/UX improvements deployed
    **2025-12-30**: Complete documentation framework with modern data sources and parallel processing workflows

## Overview

**Effective Energy and Mass Transfer (EEMT)** is a framework for quantifying energy and mass flux in Earth's Critical Zone. EEMT provides a common energy currency for understanding landscape evolution, soil formation, and biogeochemical processes across spatiotemporal scales.

$$\text{EEMT} = E_{\text{BIO}} + E_{\text{PPT}} \quad \text{[MJ m}^{-2} \text{yr}^{-1}]$$

Where:
- **E<sub>BIO</sub>** = Energy from net primary production (biological energy)
- **E<sub>PPT</sub>** = Energy from effective precipitation (thermal energy)

## Key Features

<div class="grid cards" markdown>

-   :material-rocket-launch-outline: **High Performance**

    ---

    Parallel processing with GRASS GIS r.sun.mp and modern Python workflows for continental-scale analysis

-   :material-earth: **Public Data Integration**

    ---

    Seamless integration with DAYMET, USGS 3DEP, OpenTopography, and satellite data sources

-   :material-cog: **Open Source**

    ---

    Built entirely on open-source tools: GRASS GIS, GDAL, Python, and modern geospatial libraries

-   :material-chart-line: **Multi-Scale**

    ---

    From plot-level (1m²) to continental analysis with consistent methodologies

</div>

## Quick Start

### Web Interface (Recommended)

The fastest way to get started with EEMT is through our containerized web interface:

```bash
# 1. Build Docker container (one-time setup)
cd docker/ubuntu/24.04/
./build.sh

# 2. Start web interface  
cd ../../web-interface/
pip install -r requirements.txt
python app.py

# 3. Open browser to http://127.0.0.1:5000
```

**Features:**
- 🌐 **Web-based Interface**: Upload DEMs and configure workflows through browser
- 🐳 **Containerized Execution**: All dependencies included, no complex setup
- 📊 **Real-time Monitoring**: Track progress with live updates
- 💾 **Easy Results**: Download processed data as ZIP archives

### Command Line Interface

For advanced users, EEMT can be run directly:

```bash
# 1. Install Dependencies
conda install -c conda-forge grass gdal rasterio xarray dask

# 2. Run Solar Radiation Workflow
cd sol/sol/
python run-workflow --step 15 --num_threads 4 your_dem.tif

# 3. Run Full EEMT Analysis  
cd ../../eemt/eemt/
python run-workflow --start-year 2020 --end-year 2020 your_dem.tif
```

## Scientific Foundation

EEMT calculations are based on peer-reviewed methodologies:

| Method | Reference | Key Innovation |
|--------|-----------|----------------|
| **Traditional** | Rasmussen et al. (2005) | Climate-based energy flux |
| **Topographic** | Rasmussen et al. (2014) | Terrain-modified energy/water balance |
| **Vegetation** | Rasmussen et al. (2014) | Full LAI and biomass integration |
| **HPC Implementation** | Swetnam et al. (2016) | Parallel processing framework |

## Typical EEMT Values by Climate Zone

<div class="climate-zone arid">
<strong>Arid Ecosystems</strong><br>
<span class="eemt-range">5-15 MJ/m²/yr</span><br>
Desert scrub, water-limited systems
</div>

<div class="climate-zone semiarid">
<strong>Semiarid Ecosystems</strong><br>
<span class="eemt-range">15-35 MJ/m²/yr</span><br>
Grasslands, oak woodlands, transition zones
</div>

<div class="climate-zone humid">
<strong>Humid Ecosystems</strong><br>
<span class="eemt-range">35-70 MJ/m²/yr</span><br>
Coniferous forests, energy-limited systems
</div>

## Applications

### Research Applications
- **Soil formation modeling**: Predict pedogenesis rates across landscapes
- **Critical Zone evolution**: Understand long-term landscape development  
- **Biogeochemical cycling**: Quantify carbon and nutrient fluxes
- **Climate change impacts**: Assess ecosystem sensitivity to warming

### Operational Applications  
- **Land management**: Optimize restoration and conservation strategies
- **Agricultural planning**: Site-specific productivity assessments
- **Urban planning**: Heat island mitigation and green infrastructure
- **Risk assessment**: Drought, fire, and erosion hazard mapping

## Getting Started

<div class="grid cards" markdown>

-   :material-api: [**API**](web-interface/index.md)

    ---

    Web interface, REST API, and command-line tools

-   :material-book-open-page-variant: [**Getting Started Guide**](getting-started/index.md)

    ---

    Installation, setup, and your first EEMT calculation

-   :material-database: [**Data Sources**](data-sources/index.md)

    ---

    Access elevation and climate data from public repositories

-   :material-workflow: [**Calculation Methods**](workflows/index.md)

    ---

    Step-by-step workflows for all three EEMT approaches

</div>

## Community

### Contributing
We welcome contributions to improve EEMT methods, add new examples, and extend functionality. See our [Development Guide](development/index.md).

### Support  
- **GitHub Issues**: Report bugs and request features
- **Discussions**: Ask scientific methodology questions
- **Examples**: Share use cases and workflows

### Citation

If you use EEMT in your research, please cite:

!!! quote "Primary Citation"
    Rasmussen, C., Pelletier, J.D., Troch, P.A., Swetnam, T.L., and Chorover, J. (2015). Quantifying topographic and vegetation effects on the transfer of energy and mass to the critical zone. *Vadose Zone Journal*, 14(1). [doi:10.2136/vzj2014.07.0102](https://doi.org/10.2136/vzj2014.07.0102)

For high-performance computing implementations:

!!! quote "HPC Citation"  
    Swetnam, T.L., Pelletier, J.D., Rasmussen, C., Callahan, N.R., Merchant, N., and Lyons, E. (2016). Scaling GIS analysis tasks from the desktop to the cloud utilizing contemporary distributed computing and data management approaches. *Proceedings of XSEDE16*. [doi:10.1145/2949550.2949573](https://doi.org/10.1145/2949550.2949573)

---

<div align="center">
  <p>
    <strong>EEMT</strong> is developed and maintained by the <a href="https://czo-archive.criticalzone.org/catalina-jemez/">Critical Zone Observatory</a> community<br>
    <em>Advancing understanding of Earth's Critical Zone through quantitative energy analysis</em>
  </p>
</div>