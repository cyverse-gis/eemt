// CUDA kernel for full-day solar radiation computation with horizon shading.
//
// Port of rsun-core compute_day() + solar.rs + radiation.rs to CUDA.
// Each thread processes one pixel for one day.
//
// Grid: (n_pixels + 255) / 256 blocks
// Block: 256 threads

#define PI 3.14159265358979323846f
#define PI2 (2.0f * PI)
#define HOURANGLE (PI / 12.0f)
#define RAD2DEG (180.0f / PI)

// ---- Solar functions (from solar.rs) ----

__device__ float declination(int day) {
    float d1 = PI2 * (float)day / 365.25f;
    float arg = d1 - 1.4f + 0.0355f * sinf(d1 - 0.0489f);
    float x = 0.3978f * sinf(arg);
    x = fminf(fmaxf(x, -1.0f), 1.0f);
    return asinf(x);
}

__device__ float corrected_solar_constant(int day, float solar_constant) {
    float d1 = PI2 * (float)day / 365.25f;
    return solar_constant * (1.0f + 0.03344f * cosf(d1 - 0.048869f));
}

__device__ void sunrise_sunset(float latitude, float decl, float* rise, float* set) {
    float sin_lat = sinf(latitude);
    float cos_lat = cosf(latitude);
    float cos_decl = cosf(decl);
    float sin_decl = sinf(decl);
    float lum_c31 = cos_lat * cos_decl;
    float lum_c33 = sin_lat * sin_decl;

    if (fabsf(lum_c31) < 1e-4f) {
        if (lum_c33 > 0.0f) { *rise = 0.0f; *set = 24.0f; }
        else { *rise = 12.0f; *set = 12.0f; }
        return;
    }

    float pom = -lum_c33 / lum_c31;
    if (fabsf(pom) <= 1.0f) {
        float pom_deg = acosf(pom) * RAD2DEG;
        *rise = (90.0f - pom_deg) / 15.0f + 6.0f;
        *set = (pom_deg - 90.0f) / 15.0f + 18.0f;
    } else if (pom < 0.0f) {
        *rise = 0.0f; *set = 24.0f;
    } else {
        *rise = 12.0f; *set = 12.0f;
    }
}

__device__ void solar_position(float latitude, float decl, float time_angle,
                                float* solar_alt, float* solar_az) {
    float sin_lat = sinf(latitude);
    float cos_lat = cosf(latitude);
    float cos_decl = cosf(decl);
    float sin_decl = sinf(decl);

    float lum_c11 = sin_lat * cos_decl;
    float lum_c13 = -cos_lat * sin_decl;
    float lum_c22 = cos_decl;
    float lum_c31 = cos_lat * cos_decl;
    float lum_c33 = sin_lat * sin_decl;

    float cos_time = cosf(time_angle);
    float sin_time = sinf(time_angle);

    float lum_lx = -lum_c22 * sin_time;
    float lum_ly = lum_c11 * cos_time + lum_c13;
    float sin_solar_alt = lum_c31 * cos_time + lum_c33;

    *solar_alt = asinf(fminf(fmaxf(sin_solar_alt, -1.0f), 1.0f));

    float pom = sqrtf(lum_lx * lum_lx + lum_ly * lum_ly);
    if (pom > 1e-4f) {
        float az = acosf(fminf(fmaxf(lum_ly / pom, -1.0f), 1.0f));
        if (lum_lx < 0.0f) az = PI2 - az;
        *solar_az = az;
    } else {
        *solar_az = 0.0f;
    }
}

// ---- Radiation functions (from radiation.rs) ----

__device__ void brad(float s0, float solar_alt, float elevation, float linke,
                     float cbh, float g_norm_extra,
                     float* beam_tilted, float* beam_h) {
    if (s0 <= 0.0f || solar_alt <= 0.0f) {
        *beam_tilted = 0.0f; *beam_h = 0.0f; return;
    }

    float sin_solar_alt = sinf(solar_alt);

    // Atmospheric refraction
    float temp1 = 0.1594f + solar_alt * (1.123f + 0.065656f * solar_alt);
    float temp2 = 1.0f + solar_alt * (28.9344f + 277.3971f * solar_alt);
    float drefract = 0.061359f * temp1 / temp2;
    float h0refract = solar_alt + drefract;

    // Elevation correction
    float elevation_corr = expf(-elevation / 8434.5f);

    // Optical air mass (Kasten & Young 1989)
    float optical_air_mass = elevation_corr /
        (sinf(h0refract) + 0.50572f * powf(h0refract * RAD2DEG + 6.07995f, -1.6364f));

    // Rayleigh optical thickness
    float air_mass_2_linke = 0.8662f * linke;
    float rayl;
    if (optical_air_mass <= 20.0f) {
        rayl = 1.0f / (6.6296f + optical_air_mass *
            (1.7513f + optical_air_mass *
                (-0.1202f + optical_air_mass * (0.0065f - optical_air_mass * 0.00013f))));
    } else {
        rayl = 1.0f / (10.4f + 0.718f * optical_air_mass);
    }

    *beam_h = cbh * g_norm_extra * sin_solar_alt *
              expf(-rayl * optical_air_mass * air_mass_2_linke);
    *beam_tilted = (*beam_h) * s0 / sin_solar_alt;
}

__device__ void drad(float s0, float beam_h_val, float solar_alt, float solar_azimuth,
                     float slope, float aspect, float linke, float albedo,
                     float cdh, float g_norm_extra,
                     float* diffuse, float* reflected) {
    float sin_solar_alt = sinf(solar_alt);
    float cos_slope = cosf(slope);
    float sin_slope = sinf(slope);

    // Diffuse transmission (Suri model)
    float tn = -0.015843f + linke * (0.030543f + 0.0003797f * linke);
    float a1b = 0.26463f + linke * (-0.061581f + 0.0031408f * linke);
    float a1 = (a1b * tn < 0.0022f) ? (0.0022f / tn) : a1b;
    float a2 = 2.04020f + linke * (0.018945f - 0.011161f * linke);
    float a3 = -1.3025f + linke * (0.039231f + 0.0085079f * linke);

    float fd = a1 + a2 * sin_solar_alt + a3 * sin_solar_alt * sin_solar_alt;
    float dh = cdh * g_norm_extra * fd * tn;
    float gh = beam_h_val + dh;

    if (fabsf(slope) < 1e-6f) {
        *diffuse = dh; *reflected = 0.0f; return;
    }

    float kb = beam_h_val / (g_norm_extra * sin_solar_alt);
    float r_sky = (1.0f + cos_slope) / 2.0f;

    float a_ln = solar_azimuth - aspect;
    if (a_ln > PI) a_ln -= PI2;
    else if (a_ln < -PI) a_ln += PI2;

    float half_slope = 0.5f * slope;
    float fg = sin_slope - slope * cos_slope - PI * sinf(half_slope) * sinf(half_slope);

    float fx;
    if (s0 <= 0.0f) {
        fx = r_sky + fg * 0.252271f;
    } else if (solar_alt >= 0.1f) {
        fx = ((0.00263f - kb * (0.712f + 0.6883f * kb)) * fg + r_sky) * (1.0f - kb)
             + kb * s0 / sin_solar_alt;
    } else {
        fx = ((0.00263f - 0.712f * kb - 0.6883f * kb * kb) * fg + r_sky) * (1.0f - kb)
             + kb * sin_slope * cosf(a_ln) / (0.1f - 0.008f * solar_alt);
    }

    *diffuse = dh * fx;
    *reflected = albedo * gh * (1.0f - cos_slope) / 2.0f;
}

__device__ float cos_incidence(float slope, float aspect, float latitude,
                                float decl, float time_angle) {
    float sin_lat = sinf(latitude);
    float cos_lat = cosf(latitude);
    float cos_decl = cosf(decl);
    float sin_decl = sinf(decl);

    float cos_u = cosf(PI / 2.0f - slope); // = sin(slope)
    float sin_u = sinf(PI / 2.0f - slope); // = cos(slope)
    float cos_v = cosf(PI / 2.0f + aspect);
    float sin_v = sinf(PI / 2.0f + aspect);

    float sin_phi_l = -cos_lat * cos_u * sin_v + sin_lat * sin_u;
    float q1 = sin_lat * cos_u * sin_v + cos_lat * sin_u;

    float longit_l = (fabsf(q1) > 1e-10f) ? atanf(-cos_u * cos_v / q1) : (PI / 2.0f);

    int is_best_am = (fabsf(q1) > 1e-10f) ? ((-cos_u * cos_v / q1) > 0.0f) : 1;
    int should_be_best_am = (aspect > 0.0f && aspect <= PI) ? 1 : 0;
    float time_offset = (should_be_best_am != is_best_am) ? PI : 0.0f;

    float latid_l = asinf(fminf(fmaxf(sin_phi_l, -1.0f), 1.0f));
    float lum_c31_l = cosf(latid_l) * cos_decl;
    float lum_c33_l = sin_phi_l * sin_decl;

    return lum_c31_l * cosf(-time_angle - longit_l + time_offset) + lum_c33_l;
}

// ---- Horizon interpolation ----

__device__ float horizon_interpolate(const float* angles, int n_directions,
                                      float azimuth) {
    float az = fmodf(fmodf(azimuth, PI2) + PI2, PI2);
    float step = PI2 / (float)n_directions;
    float idx_f = az / step;
    int i0 = ((int)floorf(idx_f)) % n_directions;
    int i1 = (i0 + 1) % n_directions;
    float t = idx_f - floorf(idx_f);
    return angles[i0] + t * (angles[i1] - angles[i0]);
}

// ---- Main radiation kernel ----

extern "C" __global__ void compute_day_radiation(
    const float* __restrict__ dem,           // elevation [n_pixels]
    const float* __restrict__ slope_grid,    // slope in radians [n_pixels]
    const float* __restrict__ aspect_grid,   // aspect in degrees, GRASS CW from N [n_pixels]
    const float* __restrict__ lat_grid,      // latitude in radians [n_pixels]
    const int*   __restrict__ validity,      // 1=valid, 0=nodata [n_pixels]
    const float* __restrict__ horizons,      // horizon angles [n_pixels * n_directions] (or NULL)
    float* __restrict__ glob_rad,            // output: global radiation Wh/m² [n_pixels]
    float* __restrict__ insol_time,          // output: insolation hours [n_pixels]
    int n_pixels,
    int cols,
    int day,
    float step_h,        // time step in hours
    float linke,
    float albedo_val,
    float solar_constant,
    int n_directions,     // horizon directions (0 = no horizon shading)
    float decl_rad,       // pre-computed declination
    float g_norm_extra    // pre-computed corrected solar constant
) {
    int pixel_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (pixel_idx >= n_pixels) return;

    if (!validity[pixel_idx]) {
        glob_rad[pixel_idx] = nanf("");
        insol_time[pixel_idx] = nanf("");
        return;
    }

    float lat = lat_grid[pixel_idx];
    float elev = dem[pixel_idx];
    float slope_rad = slope_grid[pixel_idx];

    // Convert GRASS cartographic aspect (degrees CW from North) to
    // r.sun internal convention (radians, 0 = east, CCW positive)
    float asp_deg = aspect_grid[pixel_idx];
    float aspect_rad;
    if (asp_deg == 0.0f) {
        aspect_rad = 0.0f;
    } else if (asp_deg < 90.0f) {
        aspect_rad = (90.0f - asp_deg) * (PI / 180.0f);
    } else {
        aspect_rad = (450.0f - asp_deg) * (PI / 180.0f);
    }

    // Sunrise/sunset
    float sunrise_h, sunset_h;
    sunrise_sunset(lat, decl_rad, &sunrise_h, &sunset_h);

    // Snap first time step
    float first_h;
    if (sunrise_h <= 0.0f) {
        first_h = step_h;
    } else {
        float n_steps = ceilf(sunrise_h / step_h);
        first_h = n_steps * step_h;
    }

    float ha_step = step_h * HOURANGLE;
    float first_angle = (first_h - 12.0f) * HOURANGLE;
    float last_angle = (sunset_h - 12.0f) * HOURANGLE;

    // Pointer to this pixel's horizon angles (if available)
    const float* my_horizons = (n_directions > 0) ?
        &horizons[pixel_idx * n_directions] : NULL;

    float glob_acc = 0.0f;
    float insol_acc = 0.0f;

    float time_angle = first_angle;
    while (time_angle <= last_angle + 1e-9f) {
        float solar_alt, solar_az;
        solar_position(lat, decl_rad, time_angle, &solar_alt, &solar_az);

        if (solar_alt > 0.0f) {
            // Shadow check via horizon interpolation
            int shadowed = 0;
            if (my_horizons != NULL) {
                float horizon_alt = horizon_interpolate(my_horizons, n_directions, solar_az);
                shadowed = (solar_alt <= horizon_alt) ? 1 : 0;
            }

            float s0 = cos_incidence(slope_rad, aspect_rad, lat, decl_rad, time_angle);

            float beam_contrib;
            if (!shadowed && s0 > 0.0f) {
                float beam_t, beam_h_val;
                brad(s0, solar_alt, elev, linke, 1.0f, g_norm_extra, &beam_t, &beam_h_val);

                float diff_t, refl_t;
                drad(s0, beam_h_val, solar_alt, solar_az, slope_rad, aspect_rad,
                     linke, albedo_val, 1.0f, g_norm_extra, &diff_t, &refl_t);

                beam_contrib = beam_t + diff_t + refl_t;
            } else {
                // Diffuse + reflected even when shadowed
                float diff_t, refl_t;
                drad(0.0f, 0.0f, solar_alt, solar_az, slope_rad, aspect_rad,
                     linke, albedo_val, 1.0f, g_norm_extra, &diff_t, &refl_t);
                beam_contrib = diff_t + refl_t;
            }

            glob_acc += beam_contrib * step_h;

            if (!shadowed && s0 > 0.0f) {
                insol_acc += step_h;
            }
        }

        time_angle += ha_step;
    }

    glob_rad[pixel_idx] = glob_acc;
    insol_time[pixel_idx] = insol_acc;
}
