#[cfg(feature = "io")]
mod tests {
    use rsun_core::io;

    #[test]
    fn test_read_dem() {
        let dem_path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../sol/examples/mcn_10m.tif");
        if !std::path::Path::new(dem_path).exists() {
            eprintln!("Skipping test: {dem_path} not found");
            return;
        }

        let (grid, geo) = io::read_geotiff(dem_path).expect("Failed to read DEM");
        assert!(grid.rows > 0, "DEM should have rows");
        assert!(grid.cols > 0, "DEM should have cols");
        assert!(geo.x_res > 0.0, "X resolution should be positive");
        assert!(geo.y_res > 0.0, "Y resolution should be positive");

        let valid_count = (0..grid.rows)
            .flat_map(|r| (0..grid.cols).map(move |c| (r, c)))
            .filter(|(r, c)| !grid.is_nodata(*r, *c))
            .count();
        assert!(valid_count > 0, "DEM should have valid pixels");

        eprintln!("DEM: {}x{}, valid pixels: {}, CRS: {}...",
            grid.rows, grid.cols, valid_count, &geo.crs_wkt[..geo.crs_wkt.len().min(60)]);
    }

    #[test]
    fn test_write_read_roundtrip() {
        use rsun_core::types::{Grid, GeoTransform};

        let mut grid = Grid::new(5, 5, f32::NAN);
        for r in 0..5 {
            for c in 0..5 {
                grid.set(r, c, (r * 5 + c) as f32 * 100.0);
            }
        }

        let geo = GeoTransform {
            x_origin: 0.0,
            y_origin: 50.0,
            x_res: 10.0,
            y_res: 10.0,
            crs_wkt: String::new(),
        };

        let tmp = "/tmp/rsun_test_roundtrip.tif";
        io::write_geotiff(tmp, &grid, &geo, None).expect("Failed to write");

        let (grid2, geo2) = io::read_geotiff(tmp).expect("Failed to read back");
        assert_eq!(grid2.rows, 5);
        assert_eq!(grid2.cols, 5);
        assert!((geo2.x_res - 10.0).abs() < 0.01);

        for r in 0..5 {
            for c in 0..5 {
                let expected = (r * 5 + c) as f32 * 100.0;
                let actual = grid2.get(r, c);
                assert!((actual - expected).abs() < 0.01,
                    "Mismatch at ({r},{c}): expected {expected}, got {actual}");
            }
        }

        std::fs::remove_file(tmp).ok();
    }
}
