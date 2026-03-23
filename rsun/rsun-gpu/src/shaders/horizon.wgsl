// Horizon angle pre-computation compute shader.
//
// For each pixel, march along N azimuthal directions across the DEM
// and record the maximum elevation angle to the horizon.
//
// Each thread handles one pixel for one direction.
// Dispatch: ceil(n_pixels / 64) workgroups per direction, iterated over directions.

struct HorizonParams {
    n_pixels: u32,
    cols: u32,
    rows: u32,
    n_directions: u32,
    direction_idx: u32,   // which direction this dispatch computes
    ew_res: f32,          // east-west cell resolution (meters)
    ns_res: f32,          // north-south cell resolution (meters)
    _pad: u32,
}

@group(0) @binding(0) var<uniform> params: HorizonParams;
@group(0) @binding(1) var<storage, read> dem: array<f32>;
@group(0) @binding(2) var<storage, read> validity: array<u32>;
@group(0) @binding(3) var<storage, read_write> horizons: array<f32>;

const PI2: f32 = 6.28318530717959;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel_idx = id.x;
    if pixel_idx >= params.n_pixels {
        return;
    }

    if validity[pixel_idx] == 0u {
        horizons[pixel_idx * params.n_directions + params.direction_idx] = 0.0;
        return;
    }

    let row = pixel_idx / params.cols;
    let col = pixel_idx % params.cols;

    let z0 = dem[pixel_idx];
    let x0 = f32(col) * params.ew_res;
    let y0 = f32(row) * params.ns_res;

    // Azimuth for this direction
    let azimuth = f32(params.direction_idx) * PI2 / f32(params.n_directions);
    let step_dist = 0.5 * (params.ew_res + params.ns_res);
    let dx = cos(azimuth) * step_dist;
    let dy = sin(azimuth) * step_dist;

    var max_angle: f32 = 0.0;
    var x = x0 + dx;
    var y = y0 + dy;

    // March along direction until out of bounds
    loop {
        let gc = i32(round(x / params.ew_res));
        let gr = i32(round(y / params.ns_res));

        // Bounds check
        if gc < 0 || gc >= i32(params.cols) || gr < 0 || gr >= i32(params.rows) {
            break;
        }

        let remote_idx = u32(gr) * params.cols + u32(gc);
        if validity[remote_idx] != 0u {
            let z_remote = dem[remote_idx];
            let dist_x = x - x0;
            let dist_y = y - y0;
            let dist = sqrt(dist_x * dist_x + dist_y * dist_y);
            if dist > 1e-6 {
                let angle = atan2(z_remote - z0, dist);
                if angle > max_angle {
                    max_angle = angle;
                }
            }
        }

        x += dx;
        y += dy;
    }

    horizons[pixel_idx * params.n_directions + params.direction_idx] = max_angle;
}
