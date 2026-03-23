use approx::assert_relative_eq;
use rsun_core::terrain;
use rsun_core::types::Grid;

#[test]
fn test_flat_terrain() {
    let mut dem = Grid::new(5, 5, f32::NAN);
    for r in 0..5 {
        for c in 0..5 {
            dem.set(r, c, 100.0);
        }
    }
    let (slope, _aspect) = terrain::slope_aspect(&dem, 10.0, 10.0);
    assert_relative_eq!(slope.get(2, 2), 0.0, epsilon = 0.01);
}

#[test]
fn test_north_facing_slope() {
    // North-facing slope: elevation increases going south (row index increases),
    // so the terrain is high in the south and low in the north.
    // Water flows north => the slope faces north => aspect near 0/360.
    let mut dem = Grid::new(5, 5, f32::NAN);
    for r in 0..5 {
        for c in 0..5 {
            dem.set(r, c, r as f32 * 10.0);
        }
    }
    let (slope, aspect) = terrain::slope_aspect(&dem, 10.0, 10.0);
    assert!(slope.get(2, 2) > 0.0, "Should have non-zero slope");
    // North-facing: aspect should be near 0 or 360 degrees
    let a = aspect.get(2, 2);
    assert!(a < 45.0 || a > 315.0, "North-facing slope aspect should be near 0/360: got {a}");
}
