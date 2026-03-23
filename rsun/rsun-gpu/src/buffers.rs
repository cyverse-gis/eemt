//! GPU buffer management for raster grids.
//!
//! Handles upload of rsun-core Grid data to GPU storage buffers
//! and readback of computed results.

use crate::context::GpuContext;
use rsun_core::types::Grid;
use wgpu;
use wgpu::util::DeviceExt;

/// A set of GPU buffers for solar radiation computation.
pub struct GpuBuffers {
    /// DEM elevation [f32, rows*cols]
    pub dem: wgpu::Buffer,
    /// Slope [f32, rows*cols] in radians
    pub slope: wgpu::Buffer,
    /// Aspect [f32, rows*cols] in radians (r.sun internal convention)
    pub aspect: wgpu::Buffer,
    /// Latitude [f32, rows*cols] in radians
    pub latitude: wgpu::Buffer,
    /// Longitude [f32, rows*cols] in radians
    pub longitude: wgpu::Buffer,
    /// Validity mask [u32, rows*cols] — 1 = valid, 0 = nodata
    pub validity: wgpu::Buffer,
    /// Global radiation output [f32, rows*cols]
    pub glob_rad: wgpu::Buffer,
    /// Insolation time output [f32, rows*cols]
    pub insol_time: wgpu::Buffer,
    /// Staging buffer for readback
    pub staging: wgpu::Buffer,
    /// Grid dimensions
    pub rows: u32,
    pub cols: u32,
    pub n_pixels: u32,
}

impl GpuBuffers {
    /// Create GPU buffers from rsun-core Grid data.
    ///
    /// Uploads DEM, slope, aspect, lat, lon to GPU.
    /// Creates empty output buffers for glob_rad and insol_time.
    pub fn new(
        ctx: &GpuContext,
        dem: &Grid,
        slope: &Grid,
        aspect: &Grid,
        lat: &Grid,
        lon: &Grid,
    ) -> Self {
        let n_pixels = (dem.rows * dem.cols) as u32;
        let buf_size = (n_pixels as u64) * 4; // f32 = 4 bytes

        // Build validity mask
        let validity_data: Vec<u32> = (0..dem.rows)
            .flat_map(|r| {
                (0..dem.cols).map(move |c| if dem.is_nodata(r, c) { 0u32 } else { 1u32 })
            })
            .collect();

        let dem_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("dem"),
            contents: bytemuck::cast_slice(&dem.data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let slope_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("slope"),
            contents: bytemuck::cast_slice(&slope.data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let aspect_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("aspect"),
            contents: bytemuck::cast_slice(&aspect.data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let lat_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("latitude"),
            contents: bytemuck::cast_slice(&lat.data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let lon_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("longitude"),
            contents: bytemuck::cast_slice(&lon.data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let validity_buf = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("validity"),
            contents: bytemuck::cast_slice(&validity_data),
            usage: wgpu::BufferUsages::STORAGE,
        });

        let glob_rad_buf = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("glob_rad"),
            size: buf_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let insol_time_buf = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("insol_time"),
            size: buf_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let staging_buf = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("staging"),
            size: buf_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        GpuBuffers {
            dem: dem_buf,
            slope: slope_buf,
            aspect: aspect_buf,
            latitude: lat_buf,
            longitude: lon_buf,
            validity: validity_buf,
            glob_rad: glob_rad_buf,
            insol_time: insol_time_buf,
            staging: staging_buf,
            rows: dem.rows as u32,
            cols: dem.cols as u32,
            n_pixels,
        }
    }

    /// Read back a GPU buffer to CPU as Vec<f32>.
    pub fn readback(&self, ctx: &GpuContext, source: &wgpu::Buffer) -> Vec<f32> {
        let buf_size = (self.n_pixels as u64) * 4;

        let mut encoder = ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("readback_encoder"),
        });
        encoder.copy_buffer_to_buffer(source, 0, &self.staging, 0, buf_size);
        ctx.queue.submit(Some(encoder.finish()));

        let buffer_slice = self.staging.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });
        ctx.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().expect("Buffer readback failed");

        let data = buffer_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data).to_vec();
        drop(data);
        self.staging.unmap();

        result
    }

    /// Read back glob_rad buffer as a Grid.
    pub fn readback_glob_rad(&self, ctx: &GpuContext) -> Grid {
        let data = self.readback(ctx, &self.glob_rad);
        Grid {
            data,
            rows: self.rows as usize,
            cols: self.cols as usize,
            nodata: f32::NAN,
        }
    }

    /// Read back insol_time buffer as a Grid.
    pub fn readback_insol_time(&self, ctx: &GpuContext) -> Grid {
        let data = self.readback(ctx, &self.insol_time);
        Grid {
            data,
            rows: self.rows as usize,
            cols: self.cols as usize,
            nodata: f32::NAN,
        }
    }
}
