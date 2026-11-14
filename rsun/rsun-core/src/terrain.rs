//! Terrain derivatives: slope and aspect from DEM.
//! Uses 3x3 finite difference method (Horn's method),
//! matching GRASS GIS r.slope.aspect.

use crate::types::Grid;

/// Compute slope and aspect from a DEM using Horn's method.
/// Returns (slope_grid, aspect_grid) where:
/// - slope is in radians (0 = flat, pi/2 = vertical)
/// - aspect is in GRASS cartographic convention: degrees clockwise from north
///   (0/360=north, 90=east, 180=south, 270=west)
/// Edge pixels are set to nodata.
pub fn slope_aspect(dem: &Grid, ew_res: f64, ns_res: f64) -> (Grid, Grid) {
    let nodata = f32::NAN;
    let mut slope = Grid::new(dem.rows, dem.cols, nodata);
    let mut aspect = Grid::new(dem.rows, dem.cols, nodata);

    for r in 1..dem.rows - 1 {
        for c in 1..dem.cols - 1 {
            // Check for nodata in 3x3 neighborhood
            let mut has_nodata = false;
            for dr in 0..3 {
                for dc in 0..3 {
                    if dem.is_nodata(r + dr - 1, c + dc - 1) {
                        has_nodata = true;
                    }
                }
            }
            if has_nodata {
                continue;
            }

            let z = |dr: i32, dc: i32| -> f64 {
                dem.get((r as i32 + dr) as usize, (c as i32 + dc) as usize) as f64
            };

            // Horn's method (3x3 weighted differences)
            let dz_dx = ((z(1, 1) + 2.0 * z(0, 1) + z(-1, 1))
                - (z(1, -1) + 2.0 * z(0, -1) + z(-1, -1)))
                / (8.0 * ew_res);

            let dz_dy = ((z(-1, -1) + 2.0 * z(-1, 0) + z(-1, 1))
                - (z(1, -1) + 2.0 * z(1, 0) + z(1, 1)))
                / (8.0 * ns_res);

            let slope_rad = (dz_dx * dz_dx + dz_dy * dz_dy).sqrt().atan();
            slope.set(r, c, slope_rad as f32);

            if slope_rad.abs() < 1e-10 {
                aspect.set(r, c, 0.0);
            } else {
                // GRASS cartographic convention: clockwise from north
                // atan2(dz_dx, -dz_dy) gives clockwise-from-north directly
                let asp = dz_dx.atan2(-dz_dy).to_degrees();
                let asp = if asp < 0.0 { asp + 360.0 } else { asp };
                aspect.set(r, c, asp as f32);
            }
        }
    }

    (slope, aspect)
}
