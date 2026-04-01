//! CUDA-accelerated solar radiation computation for rsun.
//!
//! Uses cudarc for CUDA runtime access with NVRTC for JIT kernel compilation.
//! No buffer size limits beyond available VRAM (80 GB on A100, 160 GB with NVLink).
//!
//! Two pipelines:
//! - `CudaHorizonContext::compute_horizons()` — horizon pre-computation
//! - `CudaRadiationContext::compute_day()` — full daily radiation with horizon shading

use cudarc::driver::{CudaContext, CudaFunction, CudaModule, CudaSlice, LaunchConfig, PushKernelArg};
use cudarc::nvrtc;
use rsun_core::horizon::HorizonGrid;
use rsun_core::types::{DayResult, Grid, SolarParams};
use std::sync::Arc;

const HORIZON_KERNEL_SRC: &str = include_str!("kernels/horizon.cu");
const RADIATION_KERNEL_SRC: &str = include_str!("kernels/radiation.cu");

// ==========================================================================
// Horizon Pipeline
// ==========================================================================

/// CUDA context for horizon computation.
pub struct CudaHorizonContext {
    ctx: Arc<CudaContext>,
    pub device_name: String,
    pub vram_bytes: usize,
}

impl CudaHorizonContext {
    pub fn new(device_idx: usize) -> Result<Self, String> {
        let ctx = CudaContext::new(device_idx)
            .map_err(|e| format!("Failed to create CUDA context on device {device_idx}: {e}"))?;
        let device_name = ctx.name()
            .unwrap_or_else(|_| format!("CUDA device {device_idx}"));
        Ok(CudaHorizonContext { ctx, device_name, vram_bytes: 0 })
    }

    pub fn compute_horizons(
        &self,
        dem: &Grid,
        ew_res: f64,
        ns_res: f64,
        n_directions: usize,
    ) -> Result<HorizonGrid, String> {
        let rows = dem.rows;
        let cols = dem.cols;
        let n_pixels = rows * cols;

        let validity: Vec<i32> = (0..n_pixels)
            .map(|i| if dem.is_nodata(i / cols, i % cols) { 0i32 } else { 1i32 })
            .collect();

        let ptx = nvrtc::compile_ptx(HORIZON_KERNEL_SRC)
            .map_err(|e| format!("NVRTC horizon compilation failed: {e}"))?;
        let module = self.ctx.load_module(ptx)
            .map_err(|e| format!("Failed to load horizon module: {e}"))?;
        let func = module.load_function("compute_horizon")
            .map_err(|e| format!("Failed to load compute_horizon: {e}"))?;

        let stream = self.ctx.default_stream();
        let d_dem = stream.memcpy_stod(&dem.data)
            .map_err(|e| format!("Failed to upload DEM: {e}"))?;
        let d_validity = stream.memcpy_stod(&validity)
            .map_err(|e| format!("Failed to upload validity: {e}"))?;

        let total_angles = n_pixels * n_directions;
        let mut d_angles: CudaSlice<f32> = stream.alloc_zeros(total_angles)
            .map_err(|e| format!("Failed to allocate horizon buffer ({:.1} GB): {e}",
                (total_angles * 4) as f64 / 1e9))?;

        let block_size = 256u32;
        let grid_size = ((n_pixels as u32) + block_size - 1) / block_size;
        let cfg = LaunchConfig { grid_dim: (grid_size, 1, 1), block_dim: (block_size, 1, 1), shared_mem_bytes: 0 };

        let rows_i32 = rows as i32;
        let cols_i32 = cols as i32;
        let n_dirs_i32 = n_directions as i32;
        let ew_res_f32 = ew_res as f32;
        let ns_res_f32 = ns_res as f32;

        for dir in 0..n_directions {
            let dir_i32 = dir as i32;
            unsafe {
                stream.launch_builder(&func)
                    .arg(&d_dem).arg(&d_validity).arg(&mut d_angles)
                    .arg(&rows_i32).arg(&cols_i32).arg(&n_dirs_i32)
                    .arg(&dir_i32).arg(&ew_res_f32).arg(&ns_res_f32)
                    .launch(cfg)
            }.map_err(|e| format!("Horizon kernel failed (dir {dir}): {e}"))?;
        }

        self.ctx.synchronize().map_err(|e| format!("CUDA sync failed: {e}"))?;
        let angles_flat: Vec<f32> = stream.memcpy_dtov(&d_angles)
            .map_err(|e| format!("Failed to read back horizons: {e}"))?;

        let azimuths: Vec<f64> = (0..n_directions)
            .map(|d| 2.0 * std::f64::consts::PI * d as f64 / n_directions as f64)
            .collect();

        Ok(HorizonGrid { angles: angles_flat, rows, cols, n_directions, azimuths })
    }

    pub fn list_devices() -> Vec<String> {
        let count = CudaContext::device_count().unwrap_or(0) as usize;
        (0..count)
            .filter_map(|i| {
                CudaContext::new(i).ok().map(|ctx| {
                    let name = ctx.name().unwrap_or_else(|_| format!("Device {i}"));
                    format!("[{i}] {name}")
                })
            })
            .collect()
    }
}

// ==========================================================================
// Radiation Pipeline
// ==========================================================================

/// CUDA-accelerated full-day radiation computation with horizon shading.
///
/// Each `compute_day()` call launches one kernel that processes all pixels
/// for a single day. The horizon grid and input data are uploaded once and
/// reused across multiple days.
pub struct CudaRadiationContext {
    ctx: Arc<CudaContext>,
    module: Arc<CudaModule>,
    func: CudaFunction,
    // Persistent GPU buffers (uploaded once, reused for all days)
    d_dem: CudaSlice<f32>,
    d_slope: CudaSlice<f32>,
    d_aspect: CudaSlice<f32>,
    d_lat: CudaSlice<f32>,
    d_validity: CudaSlice<i32>,
    d_horizons: CudaSlice<f32>,  // may be empty if no horizons
    n_pixels: usize,
    rows: usize,
    cols: usize,
    n_directions: i32,
    pub device_name: String,
}

impl CudaRadiationContext {
    /// Create a CUDA radiation context, uploading all input data to GPU.
    ///
    /// The `horizons` parameter is optional — pass `None` for no shading.
    /// All data stays on GPU until the context is dropped.
    pub fn new(
        device_idx: usize,
        dem: &Grid,
        slope: &Grid,
        aspect: &Grid,
        lat_grid: &Grid,
        horizons: Option<&HorizonGrid>,
    ) -> Result<Self, String> {
        let ctx = CudaContext::new(device_idx)
            .map_err(|e| format!("Failed to create CUDA context: {e}"))?;
        let device_name = ctx.name()
            .unwrap_or_else(|_| format!("CUDA device {device_idx}"));

        // Compile radiation kernel
        let ptx = nvrtc::compile_ptx(RADIATION_KERNEL_SRC)
            .map_err(|e| format!("NVRTC radiation compilation failed: {e}"))?;
        let module = ctx.load_module(ptx)
            .map_err(|e| format!("Failed to load radiation module: {e}"))?;
        let func = module.load_function("compute_day_radiation")
            .map_err(|e| format!("Failed to load compute_day_radiation: {e}"))?;

        let rows = dem.rows;
        let cols = dem.cols;
        let n_pixels = rows * cols;

        // Build validity mask
        let validity: Vec<i32> = (0..n_pixels)
            .map(|i| if dem.is_nodata(i / cols, i % cols) { 0i32 } else { 1i32 })
            .collect();

        let stream = ctx.default_stream();

        // Upload all input grids
        let d_dem = stream.memcpy_stod(&dem.data)
            .map_err(|e| format!("Failed to upload DEM: {e}"))?;
        let d_slope = stream.memcpy_stod(&slope.data)
            .map_err(|e| format!("Failed to upload slope: {e}"))?;
        let d_aspect = stream.memcpy_stod(&aspect.data)
            .map_err(|e| format!("Failed to upload aspect: {e}"))?;
        let d_lat = stream.memcpy_stod(&lat_grid.data)
            .map_err(|e| format!("Failed to upload lat: {e}"))?;
        let d_validity = stream.memcpy_stod(&validity)
            .map_err(|e| format!("Failed to upload validity: {e}"))?;

        // Upload horizon grid if provided
        let (d_horizons, n_directions) = if let Some(hg) = horizons {
            let dh = stream.memcpy_stod(&hg.angles)
                .map_err(|e| format!("Failed to upload horizons: {e}"))?;
            (dh, hg.n_directions as i32)
        } else {
            // Allocate a tiny dummy buffer (CUDA needs a valid pointer)
            let dh: CudaSlice<f32> = stream.alloc_zeros(1)
                .map_err(|e| format!("Failed to allocate dummy: {e}"))?;
            (dh, 0i32)
        };

        ctx.synchronize().map_err(|e| format!("Upload sync failed: {e}"))?;

        Ok(CudaRadiationContext {
            ctx, module, func,
            d_dem, d_slope, d_aspect, d_lat, d_validity, d_horizons,
            n_pixels, rows, cols, n_directions, device_name,
        })
    }

    /// Compute radiation for a single day. Returns DayResult with glob_rad and insol_time.
    ///
    /// This dispatches one kernel covering all pixels. The kernel handles
    /// the full sunrise→sunset time loop, solar geometry, beam/diffuse/reflected
    /// radiation, and horizon shadow checks per pixel.
    pub fn compute_day(&self, params: &SolarParams) -> Result<DayResult, String> {
        let stream = self.ctx.default_stream();

        // Allocate output buffers (fresh each day since kernel overwrites)
        let mut d_glob_rad: CudaSlice<f32> = stream.alloc_zeros(self.n_pixels)
            .map_err(|e| format!("Failed to allocate glob_rad: {e}"))?;
        let mut d_insol: CudaSlice<f32> = stream.alloc_zeros(self.n_pixels)
            .map_err(|e| format!("Failed to allocate insol_time: {e}"))?;

        // Pre-compute day-level constants on CPU (cheap)
        let decl = rsun_core::solar::declination(params.day) as f32;
        let g_norm_extra = rsun_core::solar::corrected_solar_constant(
            params.day, params.solar_constant
        ) as f32;

        let n_pixels_i32 = self.n_pixels as i32;
        let cols_i32 = self.cols as i32;
        let day_i32 = params.day as i32;
        let step_f32 = params.step as f32;
        let linke_f32 = params.linke as f32;
        let albedo_f32 = params.albedo as f32;
        let sc_f32 = params.solar_constant as f32;
        let n_dirs = self.n_directions;

        let block_size = 256u32;
        let grid_size = ((self.n_pixels as u32) + block_size - 1) / block_size;
        let cfg = LaunchConfig {
            grid_dim: (grid_size, 1, 1),
            block_dim: (block_size, 1, 1),
            shared_mem_bytes: 0,
        };

        unsafe {
            stream.launch_builder(&self.func)
                .arg(&self.d_dem)
                .arg(&self.d_slope)
                .arg(&self.d_aspect)
                .arg(&self.d_lat)
                .arg(&self.d_validity)
                .arg(&self.d_horizons)
                .arg(&mut d_glob_rad)
                .arg(&mut d_insol)
                .arg(&n_pixels_i32)
                .arg(&cols_i32)
                .arg(&day_i32)
                .arg(&step_f32)
                .arg(&linke_f32)
                .arg(&albedo_f32)
                .arg(&sc_f32)
                .arg(&n_dirs)
                .arg(&decl)
                .arg(&g_norm_extra)
                .launch(cfg)
        }.map_err(|e| format!("Radiation kernel failed: {e}"))?;

        self.ctx.synchronize().map_err(|e| format!("Radiation sync failed: {e}"))?;

        // Read back results
        let glob_data: Vec<f32> = stream.memcpy_dtov(&d_glob_rad)
            .map_err(|e| format!("Failed to read glob_rad: {e}"))?;
        let insol_data: Vec<f32> = stream.memcpy_dtov(&d_insol)
            .map_err(|e| format!("Failed to read insol_time: {e}"))?;

        let mut glob_grid = Grid::new(self.rows, self.cols, f32::NAN);
        glob_grid.data = glob_data;
        let mut insol_grid = Grid::new(self.rows, self.cols, f32::NAN);
        insol_grid.data = insol_data;

        Ok(DayResult { day: params.day, glob_rad: glob_grid, insol_time: insol_grid })
    }
}
