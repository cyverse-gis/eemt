//! GPU device and queue management via wgpu.
//!
//! Handles adapter discovery, device creation, and provides
//! the GPU context needed by all compute operations.

use wgpu;

/// GPU compute context — holds the wgpu device and queue.
pub struct GpuContext {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub adapter_name: String,
    pub backend: String,
    pub vram_bytes: u64,
}

/// Information about an available GPU adapter.
#[derive(Debug, Clone)]
pub struct GpuInfo {
    pub name: String,
    pub backend: String,
    pub device_type: String,
    pub vram_bytes: u64,
}

impl GpuContext {
    /// Create a GPU context, preferring high-performance discrete GPUs.
    ///
    /// Returns None if no suitable GPU is found.
    pub fn new() -> Option<Self> {
        pollster::block_on(Self::new_async(None))
    }

    /// Create a GPU context using a specific adapter index from `list_adapters()`.
    pub fn with_index(index: usize) -> Option<Self> {
        pollster::block_on(Self::new_async(Some(index)))
    }

    async fn new_async(device_index: Option<usize>) -> Option<Self> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::VULKAN | wgpu::Backends::METAL | wgpu::Backends::DX12,
            ..Default::default()
        });

        let adapter = if let Some(idx) = device_index {
            let adapters: Vec<_> = instance
                .enumerate_adapters(wgpu::Backends::VULKAN | wgpu::Backends::METAL | wgpu::Backends::DX12)
                .into_iter()
                .collect();
            if idx >= adapters.len() {
                return None;
            }
            adapters.into_iter().nth(idx)?
        } else {
            instance
                .request_adapter(&wgpu::RequestAdapterOptions {
                    power_preference: wgpu::PowerPreference::HighPerformance,
                    compatible_surface: None,
                    force_fallback_adapter: false,
                })
                .await?
        };

        let info = adapter.get_info();
        let adapter_name = info.name.clone();
        let backend = format!("{:?}", info.backend);
        let vram_bytes = adapter.limits().max_buffer_size;

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("rsun-gpu"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits {
                        max_storage_buffer_binding_size: 1 << 30, // 1 GB per binding
                        max_buffer_size: 1 << 34,                  // 16 GB (u64)
                        max_compute_workgroup_size_x: 256,
                        max_compute_workgroup_size_y: 256,
                        max_compute_invocations_per_workgroup: 256,
                        ..wgpu::Limits::default()
                    },
                    memory_hints: wgpu::MemoryHints::Performance,
                },
                None,
            )
            .await
            .ok()?;

        Some(GpuContext {
            device,
            queue,
            adapter_name,
            backend,
            vram_bytes,
        })
    }

    /// List all available GPU adapters.
    pub fn list_adapters() -> Vec<GpuInfo> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        instance
            .enumerate_adapters(wgpu::Backends::all())
            .into_iter()
            .map(|adapter| {
                let info = adapter.get_info();
                GpuInfo {
                    name: info.name,
                    backend: format!("{:?}", info.backend),
                    device_type: format!("{:?}", info.device_type),
                    vram_bytes: adapter.limits().max_buffer_size,
                }
            })
            .collect()
    }
}
