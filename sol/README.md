# sol_ot
This is the version of Sol that is intended to run on OpenTopography.org.
The basic input is a DEM .tif file which is reprojected to Lambert Conformal Conic (matching the DAYMET projection).
The script generates 365 days of global radiation (Watt hours) and daily hours of light (hours) in one folder called 'daily'. It also calculates the net monthly global radiation and sun hours in another folder called 'monthly'.
