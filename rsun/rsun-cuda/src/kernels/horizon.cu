// CUDA kernel for horizon angle computation via ray-marching.
//
// Each thread processes one pixel for one azimuth direction.
// Grid: (n_pixels + 255) / 256 blocks × n_directions blocks_y
// Block: 256 threads
//
// Output layout: angles[pixel_idx * n_directions + dir_idx]

extern "C" __global__ void compute_horizon(
    const float* __restrict__ dem,        // elevation [rows * cols]
    const int* __restrict__ validity,     // 1 = valid, 0 = nodata [rows * cols]
    float* __restrict__ angles,           // output horizon angles [n_pixels * n_directions]
    int rows,
    int cols,
    int n_directions,
    int direction_idx,
    float ew_res,
    float ns_res
) {
    int pixel_idx = blockIdx.x * blockDim.x + threadIdx.x;
    int n_pixels = rows * cols;

    if (pixel_idx >= n_pixels) return;

    int row = pixel_idx / cols;
    int col = pixel_idx % cols;

    float z_local = validity[pixel_idx] ? dem[pixel_idx] : 0.0f;

    // Azimuth for this direction (0 = North, clockwise)
    float az = 2.0f * 3.14159265358979f * (float)direction_idx / (float)n_directions;

    // Step vector in pixel coordinates
    float step_dist = 0.5f * (ew_res + ns_res);
    float dx_m = sinf(az);   // eastward component
    float dy_m = cosf(az);   // northward component
    float dx_pix = dx_m * step_dist / ew_res;
    float dy_pix = -dy_m * step_dist / ns_res;  // negative: row 0 = top

    float max_angle = 0.0f;
    float cur_col = (float)col + dx_pix;
    float cur_row = (float)row + dy_pix;
    float distance = step_dist;

    // Ray-march until out of bounds
    while (true) {
        int r = __float2int_rn(cur_row);
        int c = __float2int_rn(cur_col);

        if (r < 0 || r >= rows || c < 0 || c >= cols) break;

        int idx = r * cols + c;
        float z_remote = validity[idx] ? dem[idx] : 0.0f;

        float angle = atan2f(z_remote - z_local, distance);
        if (angle > max_angle) {
            max_angle = angle;
        }

        cur_col += dx_pix;
        cur_row += dy_pix;
        distance += step_dist;
    }

    // Store result: clamp to [0, π/2]
    angles[pixel_idx * n_directions + direction_idx] = fmaxf(max_angle, 0.0f);
}
