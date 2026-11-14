//! Python bindings for rsun solar radiation library.
//!
//! Provides:
//! - rsun.compute_day() — single-day radiation computation
//! - rsun.compute_year() — full-year streaming computation
//! - rsun.compute_terrain() — slope/aspect from DEM
//! - rsun.gpu_info() — list available GPU adapters

use numpy::{PyArray2, PyReadonlyArray2, PyUntypedArrayMethods};
use pyo3::prelude::*;
use rsun_core::types::{Grid, SolarParams};

/// Convert a numpy 2D array to an rsun Grid.
fn numpy_to_grid(arr: PyReadonlyArray2<'_, f32>) -> Grid {
    let shape = arr.shape();
    let rows = shape[0];
    let cols = shape[1];
    let data: Vec<f32> = arr.as_slice().unwrap().to_vec();
    Grid {
        data,
        rows,
        cols,
        nodata: f32::NAN,
    }
}

/// Convert an rsun Grid to a numpy 2D array.
fn grid_to_numpy<'py>(py: Python<'py>, grid: &Grid) -> Bound<'py, PyArray2<f32>> {
    PyArray2::from_vec2(py, &grid_to_vec2(grid)).unwrap()
}

fn grid_to_vec2(grid: &Grid) -> Vec<Vec<f32>> {
    (0..grid.rows)
        .map(|r| {
            (0..grid.cols)
                .map(|c| grid.get(r, c))
                .collect()
        })
        .collect()
}

/// Result of a single-day computation, returned to Python.
#[pyclass]
struct DayResult {
    #[pyo3(get)]
    day: u16,
    glob_rad_grid: Grid,
    insol_time_grid: Grid,
}

#[pymethods]
impl DayResult {
    /// Global radiation as numpy array [Wh/m²]
    #[getter]
    fn glob_rad<'py>(&self, py: Python<'py>) -> Bound<'py, PyArray2<f32>> {
        grid_to_numpy(py, &self.glob_rad_grid)
    }

    /// Insolation time as numpy array [hours]
    #[getter]
    fn insol_time<'py>(&self, py: Python<'py>) -> Bound<'py, PyArray2<f32>> {
        grid_to_numpy(py, &self.insol_time_grid)
    }

    /// Save global radiation to GeoTIFF.
    #[cfg(feature = "pyo3/extension-module")]
    fn save_glob_rad(&self, path: &str, dem_path: Option<&str>) -> PyResult<()> {
        let geo = rsun_core::types::GeoTransform {
            x_origin: 0.0,
            y_origin: 0.0,
            x_res: 1.0,
            y_res: 1.0,
            crs_wkt: String::new(),
        };
        rsun_core::io::write_geotiff(path, &self.glob_rad_grid, &geo, dem_path)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e))
    }
}

/// Compute solar radiation for a single day.
///
/// Args:
///     dem: 2D numpy array of elevation [meters]
///     lat: 2D numpy array of latitude [radians]
///     lon: 2D numpy array of longitude [radians]
///     day: Day of year (1-366)
///     step: Time step in decimal hours (default 0.5)
///     linke: Linke turbidity factor (default 3.0)
///     albedo: Surface albedo (default 0.2)
///     gpu: Use GPU if available (default True)
///
/// Returns:
///     DayResult with .glob_rad and .insol_time numpy arrays
#[pyfunction]
#[pyo3(signature = (dem, lat, lon, day, step=0.5, linke=3.0, albedo=0.2, gpu=true))]
fn compute_day(
    dem: PyReadonlyArray2<'_, f32>,
    lat: PyReadonlyArray2<'_, f32>,
    lon: PyReadonlyArray2<'_, f32>,
    day: u16,
    step: f64,
    linke: f64,
    albedo: f64,
    gpu: bool,
) -> PyResult<DayResult> {
    let dem_grid = numpy_to_grid(dem);
    let lat_grid = numpy_to_grid(lat);
    let lon_grid = numpy_to_grid(lon);

    let (slope_grid, aspect_grid) =
        rsun_core::terrain::slope_aspect(&dem_grid, 1.0, 1.0);

    let params = SolarParams {
        day,
        step,
        linke,
        albedo,
        solar_constant: 1367.0,
    };

    // Try GPU
    if gpu {
        if let Some(ctx) = rsun_gpu::context::GpuContext::new() {
            let buffers = rsun_gpu::buffers::GpuBuffers::new(
                &ctx,
                &dem_grid,
                &slope_grid,
                &aspect_grid,
                &lat_grid,
                &lon_grid,
            );
            let pipeline = rsun_gpu::pipeline::RadiationPipeline::new(&ctx);
            let result = pipeline.compute_day(&ctx, &buffers, &params);
            return Ok(DayResult {
                day,
                glob_rad_grid: result.glob_rad,
                insol_time_grid: result.insol_time,
            });
        }
    }

    // CPU fallback
    let result = rsun_core::compute_day(
        &dem_grid,
        &slope_grid,
        &aspect_grid,
        &lat_grid,
        &lon_grid,
        None,
        &params,
    );

    Ok(DayResult {
        day,
        glob_rad_grid: result.glob_rad,
        insol_time_grid: result.insol_time,
    })
}

/// Compute solar radiation from a GeoTIFF DEM file.
///
/// Reads the DEM, computes lat/lon from CRS, slope/aspect,
/// and runs radiation for the specified day.
///
/// Args:
///     dem_path: Path to GeoTIFF DEM file
///     day: Day of year (1-366)
///     step: Time step in decimal hours (default 0.5)
///     linke: Linke turbidity factor (default 3.0)
///     albedo: Surface albedo (default 0.2)
///     gpu: Use GPU if available (default True)
///
/// Returns:
///     DayResult with .glob_rad and .insol_time numpy arrays
#[pyfunction]
#[pyo3(signature = (dem_path, day, step=0.5, linke=3.0, albedo=0.2, gpu=true))]
fn compute_day_from_file(
    dem_path: &str,
    day: u16,
    step: f64,
    linke: f64,
    albedo: f64,
    gpu: bool,
) -> PyResult<DayResult> {
    let (dem_grid, geo) = rsun_core::io::read_geotiff(dem_path)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e))?;

    let (lat_grid, lon_grid) =
        rsun_core::io::compute_latlon_grid(dem_grid.rows, dem_grid.cols, &geo)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e))?;

    let (slope_grid, aspect_grid) =
        rsun_core::terrain::slope_aspect(&dem_grid, geo.x_res, geo.y_res);

    let params = SolarParams {
        day,
        step,
        linke,
        albedo,
        solar_constant: 1367.0,
    };

    if gpu {
        if let Some(ctx) = rsun_gpu::context::GpuContext::new() {
            let buffers = rsun_gpu::buffers::GpuBuffers::new(
                &ctx, &dem_grid, &slope_grid, &aspect_grid, &lat_grid, &lon_grid,
            );
            let pipeline = rsun_gpu::pipeline::RadiationPipeline::new(&ctx);
            let result = pipeline.compute_day(&ctx, &buffers, &params);
            return Ok(DayResult {
                day,
                glob_rad_grid: result.glob_rad,
                insol_time_grid: result.insol_time,
            });
        }
    }

    let result = rsun_core::compute_day(
        &dem_grid, &slope_grid, &aspect_grid,
        &lat_grid, &lon_grid, None, &params,
    );

    Ok(DayResult {
        day,
        glob_rad_grid: result.glob_rad,
        insol_time_grid: result.insol_time,
    })
}

/// List available GPU adapters.
///
/// Returns:
///     List of dicts with 'name', 'backend', 'device_type', 'vram_bytes'
#[pyfunction]
fn gpu_info() -> Vec<std::collections::HashMap<String, String>> {
    rsun_gpu::context::GpuContext::list_adapters()
        .into_iter()
        .map(|a| {
            let mut m = std::collections::HashMap::new();
            m.insert("name".to_string(), a.name);
            m.insert("backend".to_string(), a.backend);
            m.insert("device_type".to_string(), a.device_type);
            m.insert("vram_bytes".to_string(), a.vram_bytes.to_string());
            m
        })
        .collect()
}

/// Compute slope and aspect from a 2D elevation array.
///
/// Args:
///     dem: 2D numpy array of elevation [meters]
///     ew_res: East-west cell resolution [meters]
///     ns_res: North-south cell resolution [meters]
///
/// Returns:
///     Tuple of (slope, aspect) numpy arrays.
///     slope in radians, aspect in degrees (clockwise from north).
#[pyfunction]
#[pyo3(signature = (dem, ew_res=1.0, ns_res=1.0))]
fn compute_terrain<'py>(
    py: Python<'py>,
    dem: PyReadonlyArray2<'_, f32>,
    ew_res: f64,
    ns_res: f64,
) -> (Bound<'py, PyArray2<f32>>, Bound<'py, PyArray2<f32>>) {
    let dem_grid = numpy_to_grid(dem);
    let (slope, aspect) = rsun_core::terrain::slope_aspect(&dem_grid, ew_res, ns_res);
    (grid_to_numpy(py, &slope), grid_to_numpy(py, &aspect))
}

/// rsun Python module
#[pymodule]
fn rsun(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(compute_day, m)?)?;
    m.add_function(wrap_pyfunction!(compute_day_from_file, m)?)?;
    m.add_function(wrap_pyfunction!(gpu_info, m)?)?;
    m.add_function(wrap_pyfunction!(compute_terrain, m)?)?;
    m.add_class::<DayResult>()?;
    Ok(())
}
