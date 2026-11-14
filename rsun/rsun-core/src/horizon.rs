// Horizon angle calculations using ray-marching.
//
// For each pixel and each azimuth direction, we march outward along the DEM
// and track the maximum elevation angle seen. This gives the horizon angle:
// the angular height of the terrain above the horizontal in each direction.

use rayon::prelude::*;
use crate::types::Grid;

/// Stores pre-computed horizon angles for every pixel in a DEM grid.
///
/// Layout: `angles[row * cols * n_directions + col * n_directions + dir_idx]`
pub struct HorizonGrid {
    pub angles: Vec<f32>,
    pub rows: usize,
    pub cols: usize,
    pub n_directions: usize,
    /// Direction azimuths in radians, evenly spaced over [0, 2π).
    pub azimuths: Vec<f64>,
}

impl HorizonGrid {
    /// Return the slice of horizon angles for pixel (row, col).
    /// Length is `n_directions`.
    pub fn get_angles(&self, row: usize, col: usize) -> &[f32] {
        let base = (row * self.cols + col) * self.n_directions;
        &self.angles[base..base + self.n_directions]
    }

    /// Linearly interpolate horizon angle for an arbitrary azimuth (radians).
    ///
    /// Wraps at 2π so that azimuths outside [0, 2π) are handled correctly.
    pub fn interpolate(&self, row: usize, col: usize, azimuth: f64) -> f64 {
        use std::f64::consts::PI;
        let two_pi = 2.0 * PI;

        // Normalise azimuth to [0, 2π)
        let az = ((azimuth % two_pi) + two_pi) % two_pi;

        let step = two_pi / self.n_directions as f64;
        let idx_f = az / step;
        let i0 = idx_f.floor() as usize % self.n_directions;
        let i1 = (i0 + 1) % self.n_directions;
        let t = idx_f - idx_f.floor();

        let angles = self.get_angles(row, col);
        let a0 = angles[i0] as f64;
        let a1 = angles[i1] as f64;
        a0 + t * (a1 - a0)
    }
}

/// Compute horizon angles for every pixel in `dem` using ray-marching.
///
/// # Arguments
/// * `dem` - Elevation grid (metres).  `nodata` cells are treated as 0.
/// * `ew_res` - East–west pixel size in metres (> 0).
/// * `ns_res` - North–south pixel size in metres (> 0).
/// * `n_directions` - Number of azimuth directions.  Common values: 8, 16, 36.
///
/// Directions are evenly spaced starting at azimuth 0 (North / +Y direction).
/// Azimuth increases clockwise, consistent with the GRASS r.sun convention.
///
/// Returns a `HorizonGrid` where every angle is in **radians** in [0, π/2].
pub fn compute_horizons(
    dem: &Grid,
    ew_res: f64,
    ns_res: f64,
    n_directions: usize,
) -> HorizonGrid {
    use std::f64::consts::PI;

    assert!(n_directions > 0, "n_directions must be > 0");
    assert!(ew_res > 0.0 && ns_res > 0.0, "resolutions must be positive");

    let rows = dem.rows;
    let cols = dem.cols;
    let step_dist = 0.5 * (ew_res + ns_res);

    // Pre-compute the unit step vector for each azimuth direction.
    // Azimuth 0 = North (+row direction = increasing col, wait — standard: 0 = North, meaning +Y).
    // We use a geographic convention: azimuth 0 is North (−row in raster, since row 0 is top).
    // dx = sin(az) → column displacement per unit distance
    // dy = cos(az) → row displacement (positive = north = decreasing row index)
    let azimuths: Vec<f64> = (0..n_directions)
        .map(|d| 2.0 * PI * d as f64 / n_directions as f64)
        .collect();

    let n_pixels = rows * cols;

    // Compute horizon angles in parallel over pixels.
    let angles_flat: Vec<f32> = (0..n_pixels)
        .into_par_iter()
        .flat_map(|pixel_idx| {
            let row = pixel_idx / cols;
            let col = pixel_idx % cols;

            let z_local = if dem.is_nodata(row, col) {
                0.0_f64
            } else {
                dem.get(row, col) as f64
            };

            let mut pixel_angles = vec![0.0_f32; n_directions];

            for (dir_idx, &az) in azimuths.iter().enumerate() {
                // Step vector in pixel coordinates.
                // dx_pix: fractional column step per step_dist
                // dy_pix: fractional row step per step_dist  (north = negative row)
                let dx_m = az.sin(); // eastward component
                let dy_m = az.cos(); // northward component

                let dx_pix = dx_m * step_dist / ew_res;
                let dy_pix = -dy_m * step_dist / ns_res; // negative because row 0 = top

                let mut max_angle: f64 = 0.0;
                let mut cur_col = col as f64 + dx_pix;
                let mut cur_row = row as f64 + dy_pix;
                let mut distance = step_dist;

                loop {
                    let r = cur_row.round() as i64;
                    let c = cur_col.round() as i64;

                    // Stop when out of bounds
                    if r < 0 || r >= rows as i64 || c < 0 || c >= cols as i64 {
                        break;
                    }

                    let r = r as usize;
                    let c = c as usize;

                    let z_remote = if dem.is_nodata(r, c) {
                        0.0_f64
                    } else {
                        dem.get(r, c) as f64
                    };

                    let angle = (z_remote - z_local).atan2(distance);
                    if angle > max_angle {
                        max_angle = angle;
                    }

                    cur_col += dx_pix;
                    cur_row += dy_pix;
                    distance += step_dist;
                }

                pixel_angles[dir_idx] = max_angle.max(0.0) as f32;
            }

            pixel_angles
        })
        .collect();

    HorizonGrid {
        angles: angles_flat,
        rows,
        cols,
        n_directions,
        azimuths,
    }
}
