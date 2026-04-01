//! CUDA-accelerated horizon computation for rsun.
//!
//! Uses cudarc for CUDA runtime access with NVRTC for JIT kernel compilation.
//! No buffer size limits beyond available VRAM (80 GB on A100, 160 GB with NVLink).

use cudarc::driver::{CudaContext, CudaSlice, LaunchConfig, PushKernelArg};
use cudarc::nvrtc;
use rsun_core::horizon::HorizonGrid;
use rsun_core::types::Grid;
use std::sync::Arc;

const HORIZON_KERNEL_SRC: &str = include_str!("kernels/horizon.cu");

/// CUDA context for horizon computation.
pub struct CudaHorizonContext {
    ctx: Arc<CudaContext>,
    pub device_name: String,
    pub vram_bytes: usize,
}

impl CudaHorizonContext {
    /// Create a CUDA context on the specified device (0-indexed).
    pub fn new(device_idx: usize) -> Result<Self, String> {
        let ctx = CudaContext::new(device_idx)
            .map_err(|e| format!("Failed to create CUDA context on device {device_idx}: {e}"))?;

        // Compile horizon kernel via NVRTC
        let ptx = nvrtc::compile_ptx(HORIZON_KERNEL_SRC)
            .map_err(|e| format!("NVRTC compilation failed: {e}"))?;
        let module = ctx.load_module(ptx)
            .map_err(|e| format!("Failed to load PTX module: {e}"))?;

        // Store the module so the function stays alive
        // We'll reload per-call since the module is cheap
        let _ = module;

        let device_name = ctx.name()
            .unwrap_or_else(|_| format!("CUDA device {device_idx}"));

        Ok(CudaHorizonContext {
            ctx,
            device_name,
            vram_bytes: 0, // TODO: query via cuMemGetInfo
        })
    }

    /// Compute horizon angles for the entire DEM on GPU.
    ///
    /// No buffer size limits — allocates directly via cudaMalloc.
    /// Returns a HorizonGrid compatible with rsun_core::compute_day().
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

        // Build validity mask
        let validity: Vec<i32> = (0..n_pixels)
            .map(|i| {
                let r = i / cols;
                let c = i % cols;
                if dem.is_nodata(r, c) { 0i32 } else { 1i32 }
            })
            .collect();

        // Compile and load kernel
        let ptx = nvrtc::compile_ptx(HORIZON_KERNEL_SRC)
            .map_err(|e| format!("NVRTC compilation failed: {e}"))?;
        let module = self.ctx.load_module(ptx)
            .map_err(|e| format!("Failed to load PTX module: {e}"))?;
        let func = module.load_function("compute_horizon")
            .map_err(|e| format!("Failed to load kernel function: {e}"))?;

        // Get default stream
        let stream = self.ctx.default_stream();

        // Upload DEM and validity to GPU
        let d_dem = stream.memcpy_stod(&dem.data)
            .map_err(|e| format!("Failed to upload DEM: {e}"))?;
        let d_validity = stream.memcpy_stod(&validity)
            .map_err(|e| format!("Failed to upload validity: {e}"))?;

        // Allocate output buffer: n_pixels × n_directions × f32
        let total_angles = n_pixels * n_directions;
        let mut d_angles: CudaSlice<f32> = stream.alloc_zeros(total_angles)
            .map_err(|e| format!("Failed to allocate horizon buffer ({:.1} GB): {e}",
                (total_angles * 4) as f64 / 1e9))?;

        // Launch one kernel per direction
        let block_size = 256u32;
        let grid_size = ((n_pixels as u32) + block_size - 1) / block_size;
        let cfg = LaunchConfig {
            grid_dim: (grid_size, 1, 1),
            block_dim: (block_size, 1, 1),
            shared_mem_bytes: 0,
        };

        let rows_i32 = rows as i32;
        let cols_i32 = cols as i32;
        let n_dirs_i32 = n_directions as i32;
        let ew_res_f32 = ew_res as f32;
        let ns_res_f32 = ns_res as f32;

        for dir in 0..n_directions {
            let dir_i32 = dir as i32;

            unsafe {
                stream.launch_builder(&func)
                    .arg(&d_dem)
                    .arg(&d_validity)
                    .arg(&mut d_angles)
                    .arg(&rows_i32)
                    .arg(&cols_i32)
                    .arg(&n_dirs_i32)
                    .arg(&dir_i32)
                    .arg(&ew_res_f32)
                    .arg(&ns_res_f32)
                    .launch(cfg)
            }
            .map_err(|e| format!("Kernel launch failed (dir {dir}): {e}"))?;
        }

        // Synchronize and read back
        self.ctx.synchronize()
            .map_err(|e| format!("CUDA synchronize failed: {e}"))?;

        let angles_flat: Vec<f32> = stream.memcpy_dtov(&d_angles)
            .map_err(|e| format!("Failed to read back horizons: {e}"))?;

        // Build HorizonGrid
        let azimuths: Vec<f64> = (0..n_directions)
            .map(|d| 2.0 * std::f64::consts::PI * d as f64 / n_directions as f64)
            .collect();

        Ok(HorizonGrid {
            angles: angles_flat,
            rows,
            cols,
            n_directions,
            azimuths,
        })
    }

    /// List available CUDA devices.
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
