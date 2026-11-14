use rsun_gpu::context::{GpuContext, GpuInfo};

#[test]
fn test_list_adapters() {
    let adapters = GpuContext::list_adapters();
    eprintln!("Found {} GPU adapter(s):", adapters.len());
    for (i, a) in adapters.iter().enumerate() {
        eprintln!(
            "  [{}] {} ({}, {}, max_buffer={}MB)",
            i, a.name, a.backend, a.device_type,
            a.vram_bytes / (1024 * 1024)
        );
    }
    assert!(!adapters.is_empty(), "Should find at least one GPU adapter");
}

#[test]
fn test_create_gpu_context() {
    let ctx = GpuContext::new();
    assert!(ctx.is_some(), "Should be able to create GPU context");

    let ctx = ctx.unwrap();
    eprintln!("GPU context created:");
    eprintln!("  Adapter: {}", ctx.adapter_name);
    eprintln!("  Backend: {}", ctx.backend);
    eprintln!("  Max buffer: {} MB", ctx.vram_bytes / (1024 * 1024));

    // Should be an NVIDIA A100
    assert!(
        ctx.adapter_name.contains("A100") || ctx.adapter_name.contains("NVIDIA"),
        "Expected NVIDIA GPU, got: {}",
        ctx.adapter_name
    );
}

#[test]
fn test_simple_compute_shader() {
    // Minimal test: create a compute shader that doubles each element in a buffer.
    // This verifies the full wgpu pipeline works: shader compilation, buffer
    // creation, dispatch, readback.

    let ctx = GpuContext::new().expect("GPU context required");

    let shader_source = r#"
        @group(0) @binding(0) var<storage, read> input: array<f32>;
        @group(0) @binding(1) var<storage, read_write> output: array<f32>;

        @compute @workgroup_size(64)
        fn main(@builtin(global_invocation_id) id: vec3<u32>) {
            let i = id.x;
            if i < arrayLength(&input) {
                output[i] = input[i] * 2.0;
            }
        }
    "#;

    let shader_module = ctx.device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("test_double"),
        source: wgpu::ShaderSource::Wgsl(shader_source.into()),
    });

    // Input data
    let input_data: Vec<f32> = (0..256).map(|i| i as f32).collect();
    let input_bytes = bytemuck::cast_slice(&input_data);

    let input_buffer = ctx.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("input"),
        contents: input_bytes,
        usage: wgpu::BufferUsages::STORAGE,
    });

    let output_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("output"),
        size: (input_data.len() * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });

    let staging_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("staging"),
        size: (input_data.len() * 4) as u64,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    // Pipeline
    let bind_group_layout = ctx.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("test_layout"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: true },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: false },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
        ],
    });

    let pipeline_layout = ctx.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("test_pipeline_layout"),
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });

    let pipeline = ctx.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("test_pipeline"),
        layout: Some(&pipeline_layout),
        module: &shader_module,
        entry_point: Some("main"),
        compilation_options: Default::default(),
        cache: None,
    });

    let bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("test_bind_group"),
        layout: &bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: input_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: output_buffer.as_entire_binding(),
            },
        ],
    });

    // Dispatch
    let mut encoder = ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("test_encoder"),
    });
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("test_pass"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups((input_data.len() as u32 + 63) / 64, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&output_buffer, 0, &staging_buffer, 0, (input_data.len() * 4) as u64);
    ctx.queue.submit(Some(encoder.finish()));

    // Readback
    let buffer_slice = staging_buffer.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).unwrap();
    });
    ctx.device.poll(wgpu::Maintain::Wait);
    rx.recv().unwrap().expect("Buffer map failed");

    let data = buffer_slice.get_mapped_range();
    let output: &[f32] = bytemuck::cast_slice(&data);

    // Verify: each element should be doubled
    for i in 0..256 {
        let expected = i as f32 * 2.0;
        assert!(
            (output[i] - expected).abs() < 0.001,
            "output[{i}] = {}, expected {expected}",
            output[i]
        );
    }

    drop(data);
    staging_buffer.unmap();

    eprintln!("Compute shader test PASSED: 256 elements doubled on GPU");
}

use wgpu;
use wgpu::util::DeviceExt;
use bytemuck;
