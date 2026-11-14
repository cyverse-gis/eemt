use rsun_core::horizon::compute_horizons;
use rsun_core::types::Grid;

/// Helper: build a flat DEM at a constant elevation.
fn flat_dem(rows: usize, cols: usize, elevation: f32) -> Grid {
    let mut g = Grid::new(rows, cols, f32::NAN);
    for r in 0..rows {
        for c in 0..cols {
            g.set(r, c, elevation);
        }
    }
    g
}

/// On a perfectly flat terrain every horizon angle must be ≈ 0 radians.
#[test]
fn test_flat_terrain_zero_horizon() {
    let dem = flat_dem(20, 20, 100.0);
    let ew_res = 10.0_f64;
    let ns_res = 10.0_f64;
    let n_directions = 8;

    let hg = compute_horizons(&dem, ew_res, ns_res, n_directions);

    for row in 0..20 {
        for col in 0..20 {
            let angles = hg.get_angles(row, col);
            for &a in angles {
                assert!(
                    a.abs() < 1e-5,
                    "Expected ~0 horizon angle at ({row},{col}), got {a}"
                );
            }
        }
    }
}

/// A tall wall on the east side (cols >= 15) should produce a high eastward
/// horizon angle for a pixel well to the west (row=10, col=5).
///
/// With ew_res = ns_res = 10 m and the wall at col 15:
///   horizontal distance ≈ (15 – 5) * 10 = 100 m
///   wall height relative to base = 1000 m
///   expected angle ≈ atan2(1000, 100) ≈ 84.3° ≈ 1.47 rad
///
/// We check that the eastward horizon angle is > 45° (> π/4 rad).
#[test]
fn test_wall_blocks_horizon() {
    let rows = 20;
    let cols = 20;
    let base_elev = 0.0_f32;
    let wall_elev = 1000.0_f32;

    let mut dem = flat_dem(rows, cols, base_elev);
    for r in 0..rows {
        for c in 15..cols {
            dem.set(r, c, wall_elev);
        }
    }

    let ew_res = 10.0_f64;
    let ns_res = 10.0_f64;
    // Use 16 directions so that one direction is exactly East (azimuth π/2).
    let n_directions = 16;

    let hg = compute_horizons(&dem, ew_res, ns_res, n_directions);

    // East azimuth = π/2.  With 16 directions, direction index = 4 (0-indexed).
    // Verify using interpolate() as well so both APIs are exercised.
    use std::f64::consts::PI;
    let east_az = PI / 2.0; // 90°

    let interpolated = hg.interpolate(10, 5, east_az);

    // Threshold: 45° = π/4 ≈ 0.785 rad.
    assert!(
        interpolated > PI / 4.0,
        "Expected high eastward horizon angle (> π/4) at (10,5), got {interpolated:.4} rad ({:.1}°)",
        interpolated.to_degrees()
    );

    // Also check the raw per-direction angle for direction index 4 (East).
    let angles = hg.get_angles(10, 5);
    let east_dir_angle = angles[4] as f64;
    assert!(
        east_dir_angle > PI / 4.0,
        "Raw east direction angle should be > π/4, got {east_dir_angle:.4} rad ({:.1}°)",
        east_dir_angle.to_degrees()
    );
}
