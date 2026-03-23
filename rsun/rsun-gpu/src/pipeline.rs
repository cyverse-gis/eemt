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
