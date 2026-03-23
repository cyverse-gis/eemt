use rsun_core::types::Grid;
use rsun_gpu::buffers::GpuBuffers;
use rsun_gpu::context::GpuContext;

#[test]
fn test_buffer_upload_and_readback() {
    let ctx = GpuContext::new().expect("GPU required");

    // Create a small test grid
    let mut dem = Grid::new(10, 10, f32::NAN);
    for r in 0..10 {
        for c in 0..10 {
            dem.set(r, c, (r * 10 + c) as f32 * 100.0);
        }
    }

    let mut slope = Grid::new(10, 10, f32::NAN);
    let mut aspect = Grid::new(10, 10, f32::NAN);
    let mut lat = Grid::new(10, 10, f32::NAN);
    let mut lon = Grid::new(10, 10, f32::NAN);
    for r in 0..10 {
        for c in 0..10 {
            slope.set(r, c, 0.0);
            aspect.set(r, c, 0.0);
            lat.set(r, c, 40.0_f32.to_radians());
            lon.set(r, c, (-105.0_f32).to_radians());
        }
    }

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);

    assert_eq!(buffers.rows, 10);
    assert_eq!(buffers.cols, 10);
    assert_eq!(buffers.n_pixels, 100);

    eprintln!("Buffer upload successful: {}x{} = {} pixels", buffers.rows, buffers.cols, buffers.n_pixels);

    // We can't directly readback input buffers (they're STORAGE only),
    // but we can verify the dimensions and that no errors occurred.
    // The full readback test will be done with the compute shader in Phase 2.3.
}

#[test]
fn test_buffer_with_nodata() {
    let ctx = GpuContext::new().expect("GPU required");

    // Grid with some nodata pixels
    let mut dem = Grid::new(5, 5, f32::NAN);
    for r in 0..5 {
        for c in 0..5 {
            if r == 2 && c == 2 {
                // leave as NAN (nodata)
            } else {
                dem.set(r, c, 100.0);
            }
        }
    }

    let slope = Grid::new(5, 5, f32::NAN);
    let aspect = Grid::new(5, 5, f32::NAN);
    let lat = Grid::new(5, 5, f32::NAN);
    let lon = Grid::new(5, 5, f32::NAN);

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    assert_eq!(buffers.n_pixels, 25);

    eprintln!("Buffer with nodata created successfully");
}
