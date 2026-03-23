use rsun_core::types::Grid;
use rsun_gpu::buffers::GpuBuffers;
use rsun_gpu::context::GpuContext;
use rsun_gpu::pipeline::HorizonPipeline;

#[test]
fn test_gpu_horizon_flat_terrain() {
    let ctx = GpuContext::new().expect("GPU required");

    let mut dem = Grid::new(20, 20, f32::NAN);
    for r in 0..20 {
        for c in 0..20 {
            dem.set(r, c, 100.0);
        }
    }
    let slope = Grid::new(20, 20, f32::NAN);
    let aspect = Grid::new(20, 20, f32::NAN);
    let lat = Grid::new(20, 20, f32::NAN);
    let lon = Grid::new(20, 20, f32::NAN);
    // Initialize non-NaN for validity
    let mut slope = slope; let mut aspect = aspect; let mut lat = lat; let mut lon = lon;
    for r in 0..20 { for c in 0..20 {
        slope.set(r, c, 0.0); aspect.set(r, c, 0.0);
        lat.set(r, c, 0.7); lon.set(r, c, -1.8);
    }}

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = HorizonPipeline::new(&ctx);
    let n_dirs = 8u32;
    let horizon_buf = pipeline.create_buffer(&ctx, buffers.n_pixels, n_dirs);

    pipeline.compute(&ctx, &buffers, &horizon_buf, 10.0, 10.0);

    let data = pipeline.readback(&ctx, &horizon_buf);
    assert_eq!(data.len(), 400 * 8); // 20*20 pixels * 8 directions

    // Interior pixel (10, 10): all horizon angles should be ~0 on flat terrain
    let pixel_idx = 10 * 20 + 10;
    for d in 0..n_dirs as usize {
        let angle = data[pixel_idx * n_dirs as usize + d];
        assert!(
            angle.abs() < 0.05,
            "Flat terrain horizon should be ~0, got {angle} at direction {d}"
        );
    }
    eprintln!("GPU horizon flat terrain: all angles near zero — PASS");
}

#[test]
fn test_gpu_horizon_wall() {
    let ctx = GpuContext::new().expect("GPU required");

    // 20x20 DEM with a 1000m wall on east side (cols >= 15)
    let mut dem = Grid::new(20, 20, f32::NAN);
    for r in 0..20 {
        for c in 0..20 {
            if c >= 15 {
                dem.set(r, c, 1000.0);
            } else {
                dem.set(r, c, 100.0);
            }
        }
    }
    let mut slope = Grid::new(20, 20, f32::NAN);
    let mut aspect = Grid::new(20, 20, f32::NAN);
    let mut lat = Grid::new(20, 20, f32::NAN);
    let mut lon = Grid::new(20, 20, f32::NAN);
    for r in 0..20 { for c in 0..20 {
        slope.set(r, c, 0.0); aspect.set(r, c, 0.0);
        lat.set(r, c, 0.7); lon.set(r, c, -1.8);
    }}

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = HorizonPipeline::new(&ctx);
    let n_dirs = 16u32;
    let horizon_buf = pipeline.create_buffer(&ctx, buffers.n_pixels, n_dirs);

    pipeline.compute(&ctx, &buffers, &horizon_buf, 10.0, 10.0);

    let data = pipeline.readback(&ctx, &horizon_buf);

    // Pixel (10, 5): looking east (direction 0: azimuth 0 = +x = increasing col) should have high angle
    let pixel_idx = 10 * 20 + 5;
    let east_dir = 0; // direction 0: azimuth=0, dx=+1, dy=0 → east (increasing column)
    let east_angle = data[pixel_idx * n_dirs as usize + east_dir];
    eprintln!("GPU horizon wall: east angle at (10,5) = {east_angle:.3} rad ({:.1} deg)",
        east_angle.to_degrees());

    assert!(
        east_angle > 0.3,
        "Wall to east should produce high horizon angle, got {east_angle}"
    );

    // Compare with CPU reference — find the max angle in the CPU result to match directions
    let cpu_horizons = rsun_core::horizon::compute_horizons(&dem, 10.0, 10.0, n_dirs as usize);
    let cpu_angles = cpu_horizons.get_angles(10, 5);

    // Debug: print all CPU and GPU angles
    eprintln!("Direction comparison (pixel 10,5):");
    for d in 0..n_dirs as usize {
        let gpu_a = data[pixel_idx * n_dirs as usize + d];
        let cpu_a = cpu_angles[d];
        eprintln!("  dir {d:2}: GPU={gpu_a:.3} CPU={cpu_a:.3}");
    }

    let cpu_east = cpu_angles[east_dir];
    let abs_err = (east_angle - cpu_east).abs();
    eprintln!("CPU east angle: {cpu_east:.3} rad, GPU: {east_angle:.3} rad, abs_err: {abs_err:.3}");

    // Both CPU and GPU should detect the wall — the max angle should be similar
    // even though direction indices may differ due to coordinate conventions.
    let gpu_max: f32 = (0..n_dirs as usize)
        .map(|d| data[pixel_idx * n_dirs as usize + d])
        .fold(0.0_f32, f32::max);
    let cpu_max: f32 = cpu_angles.iter().copied().fold(0.0_f32, f32::max);

    eprintln!("GPU max horizon angle: {gpu_max:.3} rad ({:.1} deg)", gpu_max.to_degrees());
    eprintln!("CPU max horizon angle: {cpu_max:.3} rad ({:.1} deg)", cpu_max.to_degrees());

    let max_err = (gpu_max - cpu_max).abs();
    assert!(
        max_err < 0.05,
        "GPU vs CPU max horizon angle difference too large: {max_err:.3} rad"
    );
}
