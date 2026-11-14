//! Solar radiation components: beam (direct), diffuse, and reflected.
//!
//! Ported from GRASS GIS r.sun rsunlib.c brad() and drad() functions.
//! Implements the ESRA clear-sky radiation model.

use std::f64::consts::PI;

const RAD2DEG: f64 = 180.0 / PI;

/// Beam (direct) radiation on a tilted surface.
///
/// Port of GRASS `brad()`. Returns (beam_tilted, beam_horizontal).
///
/// # Arguments
/// * `s0` - cos(incidence angle) on tilted surface. If <= 0, surface faces away from sun.
/// * `solar_alt` - Solar altitude angle [radians]
/// * `elevation` - Ground elevation [meters]
/// * `linke` - Linke turbidity factor
/// * `cbh` - Real-sky beam coefficient (1.0 for clear sky)
/// * `g_norm_extra` - Corrected extraterrestrial irradiance [W/m²]
pub fn brad(
    s0: f64,
    solar_alt: f64,
    elevation: f64,
    linke: f64,
    cbh: f64,
    g_norm_extra: f64,
) -> (f64, f64) {
    if s0 <= 0.0 || solar_alt <= 0.0 {
        return (0.0, 0.0);
    }

    let sin_solar_alt = solar_alt.sin();

    // Atmospheric refraction correction
    let temp1 = 0.1594 + solar_alt * (1.123 + 0.065656 * solar_alt);
    let temp2 = 1.0 + solar_alt * (28.9344 + 277.3971 * solar_alt);
    let drefract = 0.061359 * temp1 / temp2;
    let h0refract = solar_alt + drefract;

    // Elevation correction for atmospheric pressure
    let elevation_corr = (-elevation / 8434.5_f64).exp();

    // Optical air mass (Kasten & Young 1989)
    let optical_air_mass = elevation_corr
        / (h0refract.sin()
            + 0.50572 * (h0refract * RAD2DEG + 6.07995).powf(-1.6364));

    // Rayleigh optical thickness
    let air_mass_2_linke = 0.8662 * linke;
    let rayl = if optical_air_mass <= 20.0 {
        1.0 / (6.6296
            + optical_air_mass
                * (1.7513
                    + optical_air_mass
                        * (-0.1202
                            + optical_air_mass * (0.0065 - optical_air_mass * 0.00013))))
    } else {
        1.0 / (10.4 + 0.718 * optical_air_mass)
    };

    // Horizontal beam irradiance
    let beam_h = cbh * g_norm_extra * sin_solar_alt
        * (-rayl * optical_air_mass * air_mass_2_linke).exp();

    // Beam on tilted surface
    let beam = beam_h * s0 / sin_solar_alt;

    (beam, beam_h)
}

/// Diffuse and reflected radiation on a tilted surface.
///
/// Port of GRASS `drad()`. Returns (diffuse, reflected).
///
/// # Arguments
/// * `s0` - cos(incidence angle) on tilted surface
/// * `beam_h` - Horizontal beam irradiance from `brad()`
/// * `solar_alt` - Solar altitude [radians]
/// * `solar_azimuth` - Solar azimuth [radians]
/// * `slope` - Surface slope [radians]
/// * `aspect` - Surface aspect [radians]
/// * `linke` - Linke turbidity factor
/// * `albedo` - Ground albedo
/// * `cdh` - Real-sky diffuse coefficient (1.0 for clear sky)
/// * `g_norm_extra` - Corrected extraterrestrial irradiance
pub fn drad(
    s0: f64,
    beam_h: f64,
    solar_alt: f64,
    solar_azimuth: f64,
    slope: f64,
    aspect: f64,
    linke: f64,
    albedo: f64,
    cdh: f64,
    g_norm_extra: f64,
) -> (f64, f64) {
    let sin_solar_alt = solar_alt.sin();
    let cos_slope = slope.cos();
    let sin_slope = slope.sin();

    // Diffuse transmission function (Suri model)
    let tn = -0.015843 + linke * (0.030543 + 0.0003797 * linke);
    let a1b = 0.26463 + linke * (-0.061581 + 0.0031408 * linke);
    let a1 = if a1b * tn < 0.0022 {
        0.0022 / tn
    } else {
        a1b
    };
    let a2 = 2.04020 + linke * (0.018945 - 0.011161 * linke);
    let a3 = -1.3025 + linke * (0.039231 + 0.0085079 * linke);

    let fd = a1 + a2 * sin_solar_alt + a3 * sin_solar_alt * sin_solar_alt;
    let dh = cdh * g_norm_extra * fd * tn; // horizontal diffuse
    let gh = beam_h + dh; // global horizontal

    // Flat surface: no geometric correction needed
    if slope.abs() < 1e-6 {
        return (dh, 0.0);
    }

    // Tilted surface corrections
    let kb = beam_h / (g_norm_extra * sin_solar_alt);
    let r_sky = (1.0 + cos_slope) / 2.0;

    let mut a_ln = solar_azimuth - aspect;
    if a_ln > PI {
        a_ln -= 2.0 * PI;
    } else if a_ln < -PI {
        a_ln += 2.0 * PI;
    }

    let fg = sin_slope - slope * cos_slope
        - PI * (0.5 * slope).sin() * (0.5 * slope).sin();

    let fx = if s0 <= 0.0 {
        // In shadow
        r_sky + fg * 0.252271
    } else if solar_alt >= 0.1 {
        ((0.00263 - kb * (0.712 + 0.6883 * kb)) * fg + r_sky) * (1.0 - kb)
            + kb * s0 / sin_solar_alt
    } else {
        // Low sun
        ((0.00263 - 0.712 * kb - 0.6883 * kb * kb) * fg + r_sky) * (1.0 - kb)
            + kb * sin_slope * a_ln.cos() / (0.1 - 0.008 * solar_alt)
    };

    let diffuse = dh * fx;
    let reflected = albedo * gh * (1.0 - cos_slope) / 2.0;

    (diffuse, reflected)
}

/// Cosine of the angle of incidence on a tilted surface.
///
/// From GRASS `lumcline2()` / Jenco formula. Returns the "s0" value
/// used by brad() and drad(). When s0 <= 0, the surface faces away from the sun.
///
/// # Arguments
/// * `slope` - Surface slope [radians]
/// * `aspect` - Surface aspect [radians, 0=east counterclockwise in GRASS convention]
/// * `latitude` - Geographic latitude [radians]
/// * `declination` - Solar declination [radians]
/// * `time_angle` - Hour angle [radians, 0 = noon]
pub fn cos_incidence(
    slope: f64,
    aspect: f64,
    latitude: f64,
    declination: f64,
    time_angle: f64,
) -> f64 {
    let sin_lat = latitude.sin();
    let cos_lat = latitude.cos();
    let cos_decl = declination.cos();
    let sin_decl = declination.sin();

    // Equivalent slope geometry (Jenco transformation)
    let cos_u = (PI / 2.0 - slope).cos(); // = sin(slope)
    let sin_u = (PI / 2.0 - slope).sin(); // = cos(slope)
    let cos_v = (PI / 2.0 + aspect).cos();
    let sin_v = (PI / 2.0 + aspect).sin();

    let sin_phi_l = -cos_lat * cos_u * sin_v + sin_lat * sin_u;
    let q1 = sin_lat * cos_u * sin_v + cos_lat * sin_u;

    let longit_l = if q1.abs() > 1e-10 {
        (-cos_u * cos_v / q1).atan()
    } else {
        PI / 2.0
    };

    // Determine if we need 12-hour shift
    let is_best_am = if q1.abs() > 1e-10 {
        (-cos_u * cos_v / q1) > 0.0
    } else {
        true
    };
    let should_be_best_am = aspect > 0.0 && aspect <= PI;
    let time_offset = if should_be_best_am != is_best_am {
        PI
    } else {
        0.0
    };

    let latid_l = sin_phi_l.asin();
    let lum_c31_l = latid_l.cos() * cos_decl;
    let lum_c33_l = sin_phi_l * sin_decl;

    let s0 = lum_c31_l * (-time_angle - longit_l + time_offset).cos() + lum_c33_l;
    s0
}
