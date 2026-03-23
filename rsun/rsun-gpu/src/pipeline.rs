//! GPU compute pipeline for solar radiation.
//!
//! Orchestrates the radiation compute shader dispatch,
//! handling uniform buffer setup and workgroup sizing.

use crate::buffers::GpuBuffers;
use crate::context::GpuContext;
use rsun_core::types::{DayResult, Grid, SolarParams};
use rsun_core::solar;
use wgpu;

/// Uniform buffer layout — must match the WGSL Params struct exactly.
#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuParams {
    day: u32,
    n_pixels: u32,
    cols: u32,
    rows: u32,
    step: f32,
    linke: f32,
    albedo: f32,
    solar_constant: f32,
    declination: f32,
    g_norm_extra: f32,
    _pad0: f32,
    _pad1: f32,
}

/// GPU radiation compute pipeline.
pub struct RadiationPipeline {
    pipeline: wgpu::ComputePipeline,
    bind_group_layout: wgpu::BindGroupLayout,
}

impl RadiationPipeline {
    /// Create the radiation compute pipeline.
    pub fn new(ctx: &GpuContext) -> Self {
        let shader_source = include_str!("shaders/radiation.wgsl");

        let shader_module = ctx.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("radiation_shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("radiation_layout"),
                    entries: &[
                        // 0: params uniform
                        bgl_entry(0, wgpu::BufferBindingType::Uniform),
                        // 1: dem (read)
                        bgl_entry(1, wgpu::BufferBindingType::Storage { read_only: true }),
                        // 2: slope (read)
                        bgl_entry(2, wgpu::BufferBindingType::Storage { read_only: true }),
                        // 3: aspect (read)
                        bgl_entry(3, wgpu::BufferBindingType::Storage { read_only: true }),
                        // 4: latitude (read)
                        bgl_entry(4, wgpu::BufferBindingType::Storage { read_only: true }),
                        // 5: validity (read)
                        bgl_entry(5, wgpu::BufferBindingType::Storage { read_only: true }),
                        // 6: glob_rad (read_write)
                        bgl_entry(6, wgpu::BufferBindingType::Storage { read_only: false }),
                        // 7: insol_time (read_write)
                        bgl_entry(7, wgpu::BufferBindingType::Storage { read_only: false }),
                    ],
                });

        let pipeline_layout = ctx
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("radiation_pipeline_layout"),
                bind_group_layouts: &[&bind_group_layout],
                push_constant_ranges: &[],
            });

        let pipeline = ctx
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("radiation_pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader_module,
                entry_point: Some("main"),
                compilation_options: Default::default(),
                cache: None,
            });

        RadiationPipeline {
            pipeline,
            bind_group_layout,
        }
    }

    /// Dispatch the radiation shader for a single day.
    pub fn compute_day(
        &self,
        ctx: &GpuContext,
        buffers: &GpuBuffers,
        params: &SolarParams,
    ) -> DayResult {
        let decl = solar::declination(params.day) as f32;
        let g_norm_extra =
            solar::corrected_solar_constant(params.day, params.solar_constant) as f32;

        let gpu_params = GpuParams {
            day: params.day as u32,
            n_pixels: buffers.n_pixels,
            cols: buffers.cols,
            rows: buffers.rows,
            step: params.step as f32,
            linke: params.linke as f32,
            albedo: params.albedo as f32,
            solar_constant: params.solar_constant as f32,
            declination: decl,
            g_norm_extra,
            _pad0: 0.0,
            _pad1: 0.0,
        };

        let params_buffer =
            ctx.device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("params"),
                    contents: bytemuck::bytes_of(&gpu_params),
                    usage: wgpu::BufferUsages::UNIFORM,
                });

        let bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("radiation_bind_group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: buffers.dem.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: buffers.slope.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: buffers.aspect.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: buffers.latitude.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: buffers.validity.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 6,
                    resource: buffers.glob_rad.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 7,
                    resource: buffers.insol_time.as_entire_binding(),
                },
            ],
        });

        // Dispatch: 64 threads per workgroup
        let workgroups = (buffers.n_pixels + 63) / 64;

        let mut encoder =
            ctx.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("radiation_encoder"),
                });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("radiation_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups(workgroups, 1, 1);
        }
        ctx.queue.submit(Some(encoder.finish()));

        // Readback results
        let glob_rad = buffers.readback_glob_rad(ctx);
        let insol_time = buffers.readback_insol_time(ctx);

        DayResult {
            day: params.day,
            glob_rad,
            insol_time,
        }
    }
}

/// Uniform buffer layout for horizon shader — must match WGSL HorizonParams.
#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuHorizonParams {
    n_pixels: u32,
    cols: u32,
    rows: u32,
    n_directions: u32,
    direction_idx: u32,
    ew_res: f32,
    ns_res: f32,
    _pad: u32,
}

/// GPU horizon pre-computation pipeline.
pub struct HorizonPipeline {
    pipeline: wgpu::ComputePipeline,
    bind_group_layout: wgpu::BindGroupLayout,
}

/// GPU horizon buffer — stores pre-computed angles on GPU.
pub struct GpuHorizonBuffer {
    pub buffer: wgpu::Buffer,
    pub staging: wgpu::Buffer,
    pub n_pixels: u32,
    pub n_directions: u32,
}

impl HorizonPipeline {
    pub fn new(ctx: &GpuContext) -> Self {
        let shader_source = include_str!("shaders/horizon.wgsl");
        let shader_module = ctx.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("horizon_shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let bind_group_layout =
            ctx.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("horizon_layout"),
                entries: &[
                    bgl_entry(0, wgpu::BufferBindingType::Uniform),
                    bgl_entry(1, wgpu::BufferBindingType::Storage { read_only: true }),
                    bgl_entry(2, wgpu::BufferBindingType::Storage { read_only: true }),
                    bgl_entry(3, wgpu::BufferBindingType::Storage { read_only: false }),
                ],
            });

        let pipeline_layout = ctx.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("horizon_pipeline_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = ctx.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("horizon_pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader_module,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        HorizonPipeline { pipeline, bind_group_layout }
    }

    /// Create horizon buffer on GPU.
    pub fn create_buffer(&self, ctx: &GpuContext, n_pixels: u32, n_directions: u32) -> GpuHorizonBuffer {
        let buf_size = (n_pixels as u64) * (n_directions as u64) * 4;

        let buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("horizons"),
            size: buf_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let staging = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("horizon_staging"),
            size: buf_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        GpuHorizonBuffer { buffer, staging, n_pixels, n_directions }
    }

    /// Compute horizon angles for all pixels and all directions.
    ///
    /// Dispatches the shader once per direction, iterating over N directions.
    pub fn compute(
        &self,
        ctx: &GpuContext,
        buffers: &GpuBuffers,
        horizon_buf: &GpuHorizonBuffer,
        ew_res: f64,
        ns_res: f64,
    ) {
        let workgroups = (buffers.n_pixels + 63) / 64;

        for dir in 0..horizon_buf.n_directions {
            let params = GpuHorizonParams {
                n_pixels: buffers.n_pixels,
                cols: buffers.cols,
                rows: buffers.rows,
                n_directions: horizon_buf.n_directions,
                direction_idx: dir,
                ew_res: ew_res as f32,
                ns_res: ns_res as f32,
                _pad: 0,
            };

            let params_buffer = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("horizon_params"),
                contents: bytemuck::bytes_of(&params),
                usage: wgpu::BufferUsages::UNIFORM,
            });

            let bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("horizon_bind_group"),
                layout: &self.bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: params_buffer.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: buffers.dem.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 2, resource: buffers.validity.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 3, resource: horizon_buf.buffer.as_entire_binding() },
                ],
            });

            let mut encoder = ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("horizon_encoder"),
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("horizon_pass"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&self.pipeline);
                pass.set_bind_group(0, &bind_group, &[]);
                pass.dispatch_workgroups(workgroups, 1, 1);
            }
            ctx.queue.submit(Some(encoder.finish()));
        }

        // Wait for all directions to complete
        ctx.device.poll(wgpu::Maintain::Wait);
    }

    /// Read back horizon data to CPU.
    pub fn readback(&self, ctx: &GpuContext, horizon_buf: &GpuHorizonBuffer) -> Vec<f32> {
        let buf_size = (horizon_buf.n_pixels as u64) * (horizon_buf.n_directions as u64) * 4;

        let mut encoder = ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("horizon_readback_encoder"),
        });
        encoder.copy_buffer_to_buffer(&horizon_buf.buffer, 0, &horizon_buf.staging, 0, buf_size);
        ctx.queue.submit(Some(encoder.finish()));

        let buffer_slice = horizon_buf.staging.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });
        ctx.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().expect("Horizon readback failed");

        let data = buffer_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data).to_vec();
        drop(data);
        horizon_buf.staging.unmap();

        result
    }
}

/// Helper to create bind group layout entries.
fn bgl_entry(binding: u32, ty: wgpu::BufferBindingType) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer {
            ty,
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    }
}

use wgpu::util::DeviceExt;
