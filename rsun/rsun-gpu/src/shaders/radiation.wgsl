// Solar radiation compute shader — GPU implementation of r.sun algorithm.
//
// Computes full-day global radiation and insolation time for each pixel.
// Ported from GRASS r.sun rsunlib.c (Hofierka & Suri 2002).
//
// Each thread handles one pixel. The time loop (sunrise→sunset) runs
// entirely within the thread — no inter-thread communication needed.

// Uniforms: parameters that are constant for the entire dispatch
struct Params {
    day: u32,
    n_pixels: u32,
    cols: u32,
    rows: u32,
    step: f32,           // time step in decimal hours
    linke: f32,          // Linke turbidity factor
    albedo: f32,         // surface albedo
    solar_constant: f32, // W/m² (typically 1367)
    declination: f32,    // solar declination in radians
    g_norm_extra: f32,   // corrected extraterrestrial irradiance
    _pad0: f32,
    _pad1: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> dem: array<f32>;
@group(0) @binding(2) var<storage, read> slope: array<f32>;
@group(0) @binding(3) var<storage, read> aspect: array<f32>;
@group(0) @binding(4) var<storage, read> latitude: array<f32>;
@group(0) @binding(5) var<storage, read> validity: array<u32>;
@group(0) @binding(6) var<storage, read_write> glob_rad: array<f32>;
@group(0) @binding(7) var<storage, read_write> insol_time: array<f32>;

const PI: f32 = 3.14159265358979;
const PI2: f32 = 6.28318530717959;
const HOURANGLE: f32 = 0.26179938779915; // PI / 12
const RAD2DEG: f32 = 57.29577951308232;

// Beam radiation (port of GRASS brad())
fn brad(s0: f32, solar_alt: f32, elevation: f32, linke: f32, g_norm_extra: f32) -> vec2<f32> {
    if s0 <= 0.0 || solar_alt <= 0.0 {
        return vec2<f32>(0.0, 0.0);
    }

    let sin_solar_alt = sin(solar_alt);

    // Atmospheric refraction correction
    let temp1 = 0.1594 + solar_alt * (1.123 + 0.065656 * solar_alt);
    let temp2 = 1.0 + solar_alt * (28.9344 + 277.3971 * solar_alt);
    let drefract = 0.061359 * temp1 / temp2;
    let h0refract = solar_alt + drefract;

    // Elevation correction
    let elevation_corr = exp(-elevation / 8434.5);

    // Optical air mass
    let optical_air_mass = elevation_corr /
        (sin(h0refract) + 0.50572 * pow(h0refract * RAD2DEG + 6.07995, -1.6364));

    // Rayleigh optical thickness
    let air_mass_2_linke = 0.8662 * linke;
    var rayl: f32;
    if optical_air_mass <= 20.0 {
        rayl = 1.0 / (6.6296 + optical_air_mass *
            (1.7513 + optical_air_mass *
                (-0.1202 + optical_air_mass *
                    (0.0065 - optical_air_mass * 0.00013))));
    } else {
        rayl = 1.0 / (10.4 + 0.718 * optical_air_mass);
    }

    let beam_h = g_norm_extra * sin_solar_alt *
        exp(-rayl * optical_air_mass * air_mass_2_linke);

    let beam = beam_h * s0 / sin_solar_alt;

    return vec2<f32>(beam, beam_h);
}

// Diffuse + reflected radiation (port of GRASS drad())
fn drad(s0: f32, beam_h: f32, solar_alt: f32, solar_azimuth: f32,
        slp: f32, asp: f32, linke: f32, albedo: f32,
        g_norm_extra: f32) -> vec2<f32> {
    let sin_solar_alt = sin(solar_alt);
    let cos_slope = cos(slp);
    let sin_slope = sin(slp);

    // Diffuse transmission (Suri model)
    let tn = -0.015843 + linke * (0.030543 + 0.0003797 * linke);
    let a1b = 0.26463 + linke * (-0.061581 + 0.0031408 * linke);
    var a1: f32;
    if a1b * tn < 0.0022 {
        a1 = 0.0022 / tn;
    } else {
        a1 = a1b;
    }
    let a2 = 2.04020 + linke * (0.018945 - 0.011161 * linke);
    let a3 = -1.3025 + linke * (0.039231 + 0.0085079 * linke);

    let fd = a1 + a2 * sin_solar_alt + a3 * sin_solar_alt * sin_solar_alt;
    let dh = g_norm_extra * fd * tn;
    let gh = beam_h + dh;

    // Flat surface
    if abs(slp) < 1e-6 {
        return vec2<f32>(dh, 0.0);
    }

    let kb = beam_h / (g_norm_extra * sin_solar_alt);
    let r_sky = (1.0 + cos_slope) / 2.0;

    var a_ln = solar_azimuth - asp;
    if a_ln > PI { a_ln -= PI2; }
    else if a_ln < -PI { a_ln += PI2; }

    let fg = sin_slope - slp * cos_slope - PI * sin(0.5 * slp) * sin(0.5 * slp);

    var fx: f32;
    if s0 <= 0.0 {
        fx = r_sky + fg * 0.252271;
    } else if solar_alt >= 0.1 {
        fx = ((0.00263 - kb * (0.712 + 0.6883 * kb)) * fg + r_sky) * (1.0 - kb)
            + kb * s0 / sin_solar_alt;
    } else {
        fx = ((0.00263 - 0.712 * kb - 0.6883 * kb * kb) * fg + r_sky) * (1.0 - kb)
            + kb * sin_slope * cos(a_ln) / (0.1 - 0.008 * solar_alt);
    }

    let diffuse = dh * fx;
    let reflected = albedo * gh * (1.0 - cos_slope) / 2.0;

    return vec2<f32>(diffuse, reflected);
}

// Cosine of incidence angle (port of GRASS lumcline2 / Jenco formula)
fn cos_incidence(slp: f32, asp: f32, lat: f32, decl: f32, time_angle: f32) -> f32 {
    let sin_lat = sin(lat);
    let cos_lat = cos(lat);
    let cos_decl = cos(decl);
    let sin_decl = sin(decl);

    let cos_u = cos(PI / 2.0 - slp); // = sin(slope)
    let sin_u = sin(PI / 2.0 - slp); // = cos(slope)
    let cos_v = cos(PI / 2.0 + asp);
    let sin_v = sin(PI / 2.0 + asp);

    let sin_phi_l = -cos_lat * cos_u * sin_v + sin_lat * sin_u;
    let q1 = sin_lat * cos_u * sin_v + cos_lat * sin_u;

    var longit_l: f32;
    var is_best_am: bool;
    if abs(q1) > 1e-10 {
        longit_l = atan(-cos_u * cos_v / q1);
        is_best_am = (-cos_u * cos_v / q1) > 0.0;
    } else {
        longit_l = PI / 2.0;
        is_best_am = true;
    }

    let should_be_best_am = asp > 0.0 && asp <= PI;
    var time_offset: f32 = 0.0;
    if should_be_best_am != is_best_am {
        time_offset = PI;
    }

    let latid_l = asin(clamp(sin_phi_l, -1.0, 1.0));
    let lum_c31_l = cos(latid_l) * cos_decl;
    let lum_c33_l = sin_phi_l * sin_decl;

    return lum_c31_l * cos(-time_angle - longit_l + time_offset) + lum_c33_l;
}

// Solar position: compute altitude and azimuth
fn solar_position(lat: f32, decl: f32, time_angle: f32) -> vec2<f32> {
    let sin_lat = sin(lat);
    let cos_lat = cos(lat);
    let cos_decl = cos(decl);
    let sin_decl = sin(decl);

    let lum_c11 = sin_lat * cos_decl;
    let lum_c13 = -cos_lat * sin_decl;
    let lum_c22 = cos_decl;
    let lum_c31 = cos_lat * cos_decl;
    let lum_c33 = sin_lat * sin_decl;

    let cos_time = cos(time_angle);
    let sin_time = sin(time_angle);

    let lum_lx = -lum_c22 * sin_time;
    let lum_ly = lum_c11 * cos_time + lum_c13;
    let sin_solar_alt = lum_c31 * cos_time + lum_c33;

    let solar_altitude = asin(clamp(sin_solar_alt, -1.0, 1.0));

    let pom = sqrt(lum_lx * lum_lx + lum_ly * lum_ly);
    var solar_azimuth: f32 = 0.0;
    if pom > 1e-4 {
        solar_azimuth = acos(clamp(lum_ly / pom, -1.0, 1.0));
        if lum_lx < 0.0 {
            solar_azimuth = PI2 - solar_azimuth;
        }
    }

    return vec2<f32>(solar_altitude, solar_azimuth);
}

// Sunrise/sunset computation
fn sunrise_sunset(lat: f32, decl: f32) -> vec2<f32> {
    let cos_lat = cos(lat);
    let cos_decl = cos(decl);
    let sin_lat = sin(lat);
    let sin_decl = sin(decl);

    let lum_c31 = cos_lat * cos_decl;
    let lum_c33 = sin_lat * sin_decl;

    if abs(lum_c31) < 1e-4 {
        if lum_c33 > 0.0 {
            return vec2<f32>(0.0, 24.0);
        } else {
            return vec2<f32>(12.0, 12.0);
        }
    }

    let pom = -lum_c33 / lum_c31;
    if abs(pom) <= 1.0 {
        let pom_deg = acos(pom) * RAD2DEG;
        let sunrise = (90.0 - pom_deg) / 15.0 + 6.0;
        let sunset = (pom_deg - 90.0) / 15.0 + 18.0;
        return vec2<f32>(sunrise, sunset);
    } else if pom < 0.0 {
        return vec2<f32>(0.0, 24.0);
    } else {
        return vec2<f32>(12.0, 12.0);
    }
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel_idx = id.x;
    if pixel_idx >= params.n_pixels {
        return;
    }

    // Skip nodata pixels — use bitcast to produce NaN (WGSL forbids 0/0 literals)
    if validity[pixel_idx] == 0u {
        glob_rad[pixel_idx] = bitcast<f32>(0x7FC00000u); // quiet NaN
        insol_time[pixel_idx] = bitcast<f32>(0x7FC00000u);
        return;
    }

    let elevation = dem[pixel_idx];
    let slp = slope[pixel_idx];
    let lat = latitude[pixel_idx];
    let decl = params.declination;
    let step_hours = params.step;
    let step_rad = step_hours * HOURANGLE;

    // Aspect conversion: GRASS cartographic (degrees CW from north) → r.sun internal (radians)
    let asp_deg = aspect[pixel_idx];
    var asp_rad: f32;
    if asp_deg == 0.0 {
        asp_rad = 0.0;
    } else if asp_deg < 90.0 {
        asp_rad = (90.0 - asp_deg) * PI / 180.0;
    } else {
        asp_rad = (450.0 - asp_deg) * PI / 180.0;
    }

    // Sunrise/sunset
    let sun_times = sunrise_sunset(lat, decl);
    let sunrise = sun_times.x;
    let sunset = sun_times.y;

    // First time step (aligned to step intervals, matching GRASS)
    let sr_step_no = i32(sunrise / step_hours);
    var first_time: f32;
    if (sunrise - f32(sr_step_no) * step_hours) > 0.5 * step_hours {
        first_time = (f32(sr_step_no) + 1.5) * step_hours;
    } else {
        first_time = (f32(sr_step_no) + 0.5) * step_hours;
    }

    let first_angle = (first_time - 12.0) * HOURANGLE;
    let last_angle = (sunset - 12.0) * HOURANGLE;

    var total_rad: f32 = 0.0;
    var total_insol: f32 = 0.0;
    var time_angle = first_angle;

    // Time integration loop: sunrise to sunset
    loop {
        if time_angle > last_angle {
            break;
        }

        let sun_pos = solar_position(lat, decl, time_angle);
        let solar_alt = sun_pos.x;
        let solar_az = sun_pos.y;

        if solar_alt > 0.0 {
            let s0 = cos_incidence(slp, asp_rad, lat, decl, time_angle);

            if s0 > 0.0 {
                // Direct beam radiation
                let beam_result = brad(s0, solar_alt, elevation, params.linke, params.g_norm_extra);
                let beam = beam_result.x;
                let beam_h = beam_result.y;

                total_rad += step_hours * beam;
                total_insol += step_hours;

                // Diffuse + reflected
                let diff_result = drad(s0, beam_h, solar_alt, solar_az,
                                       slp, asp_rad, params.linke, params.albedo,
                                       params.g_norm_extra);
                total_rad += step_hours * (diff_result.x + diff_result.y);
            } else {
                // In shadow: diffuse only
                let diff_result = drad(0.0, 0.0, solar_alt, solar_az,
                                       slp, asp_rad, params.linke, params.albedo,
                                       params.g_norm_extra);
                total_rad += step_hours * (diff_result.x + diff_result.y);
            }
        }

        time_angle += step_rad;
    }

    glob_rad[pixel_idx] = total_rad;
    insol_time[pixel_idx] = total_insol;
}
