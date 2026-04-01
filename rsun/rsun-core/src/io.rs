//! GeoTIFF I/O and coordinate transformation utilities.

#[cfg(feature = "io")]
use gdal::Dataset;

use crate::types::{GeoTransform, Grid};

/// Read a GeoTIFF file into a Grid with geographic metadata.
#[cfg(feature = "io")]
pub fn read_geotiff(path: &str) -> Result<(Grid, GeoTransform), String> {
    let dataset = Dataset::open(path).map_err(|e| format!("Failed to open {path}: {e}"))?;
    let transform = dataset.geo_transform().map_err(|e| format!("No geotransform: {e}"))?;
    let band = dataset.rasterband(1).map_err(|e| format!("No raster band: {e}"))?;
    let (cols, rows) = dataset.raster_size();
    let nodata = band.no_data_value().unwrap_or(f64::NAN) as f32;

    let buf = band
        .read_as::<f32>((0, 0), (cols, rows), (cols, rows), None)
        .map_err(|e| format!("Failed to read raster data: {e}"))?;

    let mut grid = Grid::new(rows, cols, nodata);
    grid.data = buf.data().to_vec();

    let crs_wkt = dataset.projection();

    let geo = GeoTransform {
        x_origin: transform[0],
        y_origin: transform[3],
        x_res: transform[1].abs(),
        y_res: transform[5].abs(),
        crs_wkt,
    };

    Ok((grid, geo))
}

/// Write a Grid to a GeoTIFF file.
#[cfg(feature = "io")]
pub fn write_geotiff(
    path: &str,
    grid: &Grid,
    geo: &GeoTransform,
    source_path: Option<&str>,
) -> Result<(), String> {
    use gdal::DriverManager;

    let driver = DriverManager::get_driver_by_name("GTiff")
        .map_err(|e| format!("GTiff driver not found: {e}"))?;

    let options = gdal::raster::RasterCreationOptions::from_iter([
        "COMPRESS=LZW",
        "PREDICTOR=3",  // float predictor for better LZW compression
        "TILED=YES",
    ]);

    let mut dataset = driver
        .create_with_band_type_with_options::<f32, &str>(path, grid.cols, grid.rows, 1, &options)
        .map_err(|e| format!("Failed to create output: {e}"))?;

    let transform = [geo.x_origin, geo.x_res, 0.0, geo.y_origin, 0.0, -geo.y_res];
    dataset.set_geo_transform(&transform).map_err(|e| format!("Failed to set geotransform: {e}"))?;

    if let Some(src_path) = source_path {
        if let Ok(src_ds) = Dataset::open(src_path) {
            let proj = src_ds.projection();
            if !proj.is_empty() {
                let _ = dataset.set_projection(&proj);
            }
        }
    }

    if !geo.crs_wkt.is_empty() {
        let _ = dataset.set_projection(&geo.crs_wkt);
    }

    let mut band = dataset.rasterband(1).map_err(|e| format!("Failed to get band: {e}"))?;
    band.set_no_data_value(Some(grid.nodata as f64)).map_err(|e| format!("Failed to set nodata: {e}"))?;

    let mut buf = gdal::raster::Buffer::new((grid.cols, grid.rows), grid.data.clone());
    band.write((0, 0), (grid.cols, grid.rows), &mut buf).map_err(|e| format!("Failed to write data: {e}"))?;

    Ok(())
}

/// Compute latitude/longitude grids from geographic metadata.
///
/// Handles both geographic (lat/lon) and projected CRS. For projected CRS,
/// uses GDAL's built-in coordinate transformation to reproject pixel centres
/// to WGS84 latitude/longitude.
pub fn compute_latlon_grid(
    rows: usize,
    cols: usize,
    geo: &GeoTransform,
) -> Result<(Grid, Grid), String> {
    use gdal::spatial_ref::{CoordTransform, SpatialRef};

    let mut lat_grid = Grid::new(rows, cols, f32::NAN);
    let mut lon_grid = Grid::new(rows, cols, f32::NAN);

    // Detect geographic vs projected CRS.
    // WKT2 uses "GEOGCRS"/"PROJCRS"; WKT1 uses "GEOGCS"/"PROJCS".
    let is_geographic = (geo.crs_wkt.contains("GEOGCS") || geo.crs_wkt.contains("GEOGCRS"))
        && !geo.crs_wkt.contains("PROJCS")
        && !geo.crs_wkt.contains("PROJCRS");

    if is_geographic || geo.crs_wkt.is_empty() {
        // Simple: pixel centres are already lon/lat in degrees.
        for r in 0..rows {
            for c in 0..cols {
                let lon = geo.x_origin + (c as f64 + 0.5) * geo.x_res;
                let lat = geo.y_origin - (r as f64 + 0.5) * geo.y_res;
                lat_grid.set(r, c, (lat as f32).to_radians());
                lon_grid.set(r, c, (lon as f32).to_radians());
            }
        }
    } else {
        // Projected CRS: reproject pixel centres to WGS84 using GDAL.
        let src_srs = SpatialRef::from_wkt(&geo.crs_wkt)
            .map_err(|e| format!("Failed to parse source CRS: {e}"))?;
        let mut wgs84 = SpatialRef::from_epsg(4326)
            .map_err(|e| format!("Failed to create WGS84 SRS: {e}"))?;

        // GDAL >= 3.0 returns (lat, lon) for EPSG:4326 by default; force (lon, lat) axis order.
        wgs84.set_axis_mapping_strategy(gdal::spatial_ref::AxisMappingStrategy::TraditionalGisOrder);

        let transform = CoordTransform::new(&src_srs, &wgs84)
            .map_err(|e| format!("Failed to create coordinate transform: {e}"))?;

        let n = rows * cols;
        let mut xs: Vec<f64> = Vec::with_capacity(n);
        let mut ys: Vec<f64> = Vec::with_capacity(n);

        for r in 0..rows {
            for c in 0..cols {
                xs.push(geo.x_origin + (c as f64 + 0.5) * geo.x_res);
                ys.push(geo.y_origin - (r as f64 + 0.5) * geo.y_res);
            }
        }

        transform
            .transform_coords(&mut xs, &mut ys, &mut [])
            .map_err(|e| format!("Coordinate transformation failed: {e}"))?;

        for r in 0..rows {
            for c in 0..cols {
                let idx = r * cols + c;
                let lon_deg = xs[idx];
                let lat_deg = ys[idx];
                lat_grid.set(r, c, (lat_deg as f32).to_radians());
                lon_grid.set(r, c, (lon_deg as f32).to_radians());
            }
        }
    }

    Ok((lat_grid, lon_grid))
}
