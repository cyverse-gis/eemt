//! GPU-accelerated solar radiation via wgpu compute shaders.
//!
//! Provides the same computation as rsun-core but executed on GPU
//! via WGSL compute shaders. Falls back to rsun-core CPU implementation
//! when no GPU is available.

pub mod context;
pub mod buffers;
pub mod pipeline;
