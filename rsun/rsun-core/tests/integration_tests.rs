use rsun_core::types::{Grid, SolarParams};
use rsun_core::compute_day;

#[test]
fn test_compute_day_flat_terrain() {
    // Small flat DEM at 40°N, day 172 (summer solstice)
    let mut dem = Grid::new(10, 10, f32::NAN);
    for r in 0..10 {
        for c in 0..10 {
            dem.set(r, c, 2500.0);
        }
    }

    let mut lat_grid = Grid::new(10, 10, f32::NAN);
    let mut lon_grid = Grid::new(10, 10, f32::NAN);
    let mut slope_grid = Grid::new(10, 10, f32::NAN);
    let mut aspect_grid = Grid::new(10, 10, f32::NAN);
    for r in 0..10 {
        for c in 0..10 {
            lat_grid.set(r, c, 40.0_f32.to_radians());
            lon_grid.set(r, c, (-105.0_f32).to_radians());
            slope_grid.set(r, c, 0.0);
            aspect_grid.set(r, c, 0.0);
        }
    }

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = compute_day(
        &dem, &slope_grid, &aspect_grid,
        &lat_grid, &lon_grid,
        None, &params,
    );

    let center_rad = result.glob_rad.get(5, 5);
    println!("center_rad = {center_rad} Wh/m²");
    assert!(center_rad > 1000.0, "Summer day should have >1000 Wh/m²: got {center_rad}");
    assert!(center_rad < 12000.0, "Should be <12000 Wh/m²: got {center_rad}");

    let center_insol = result.insol_time.get(5, 5);
    println!("center_insol = {center_insol} h");
    assert!(center_insol > 10.0, "Summer should have >10h sun: got {center_insol}");
    assert!(center_insol < 18.0, "Should be <18h sun: got {center_insol}");
}
