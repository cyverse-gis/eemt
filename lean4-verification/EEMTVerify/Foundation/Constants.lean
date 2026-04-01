/-
  Physical Constants for EEMT Verification
  =========================================
  All constants used across the EEMT equation library.
  Values sourced from docs/algorithms/ and rsun/rsun-core/src/types.rs
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

namespace EEMTVerify.Constants

/-! ## Solar Constants -/

/-- Solar constant at mean Earth-Sun distance [W/m²] -/
noncomputable def solarConstant : ℝ := 1367.0

/-- Maximum Earth orbital eccentricity factor (perihelion) -/
noncomputable def eccentricityMax : ℝ := 1.03344

/-- Minimum Earth orbital eccentricity factor (aphelion) -/
noncomputable def eccentricityMin : ℝ := 0.96656

/-- Earth's axial tilt (obliquity) [radians] ≈ 23.44° -/
noncomputable def obliquity : ℝ := 0.4091 -- arcsin(0.3978) ≈ 23.44°

/-- Hour angle conversion factor [radians/hour] = π/12 -/
noncomputable def hourAngle : ℝ := Real.pi / 12

/-! ## Atmospheric Constants -/

/-- Barometric scale height for elevation correction [meters] -/
noncomputable def scaleHeight : ℝ := 8434.5

/-- Default Linke turbidity factor (clear atmosphere) -/
noncomputable def defaultLinke : ℝ := 3.0

/-- Default surface albedo (vegetation) -/
noncomputable def defaultAlbedo : ℝ := 0.2

/-! ## Thermodynamic Constants -/

/-- Density of water [kg/m³] -/
noncomputable def rhoWater : ℝ := 1000.0

/-- Specific heat capacity of water [J/(kg·K)] -/
noncomputable def cWater : ℝ := 4180.0

/-- Specific enthalpy of biomass [J/kg] (from bomb calorimetry) -/
noncomputable def hBio : ℝ := 22.0e6

/-- Latent heat of vaporization [J/kg] -/
noncomputable def latentHeatVap : ℝ := 2.45e6

/-- Psychrometric constant at sea level [kPa/°C] -/
noncomputable def psychrometricConst : ℝ := 0.665

/-! ## Climate Constants -/

/-- Environmental lapse rate [°C/m] (negative: temp decreases with altitude) -/
noncomputable def lapseRate : ℝ := 0.00649

/-- Magnus formula coefficient a -/
noncomputable def magnusA : ℝ := 17.27

/-- Magnus formula coefficient b [°C] -/
noncomputable def magnusB : ℝ := 237.3

/-- Magnus formula reference pressure [kPa] -/
noncomputable def magnusRef : ℝ := 0.6108

/-- Rain temperature threshold [°C] -/
noncomputable def tempRainThreshold : ℝ := 3.0

/-- Snow temperature threshold [°C] -/
noncomputable def tempSnowThreshold : ℝ := -1.0

/-! ## NPP Constants -/

/-- Maximum NPP in Lieth model [g/m²/yr] -/
noncomputable def nppMax : ℝ := 3000.0

/-- Lieth temperature coefficient -/
noncomputable def liethTempCoeff : ℝ := 0.119

/-- Lieth temperature intercept -/
noncomputable def liethTempIntercept : ℝ := 1.315

/-- Lieth precipitation coefficient -/
noncomputable def liethPrecipCoeff : ℝ := 0.000664

/-! ## EEMT Constants -/

/-- EEMT regime transition threshold [MJ/m²/yr] -/
noncomputable def eemtRegimeThreshold : ℝ := 70.0

/-- EEMT physical minimum [MJ/m²/yr] -/
noncomputable def eemtMin : ℝ := 0.1

/-- EEMT physical maximum [MJ/m²/yr] -/
noncomputable def eemtMax : ℝ := 500.0

/-! ## Biomass Constants -/

/-- Higher heating value for Pinus species [MJ/kg] -/
noncomputable def hhvPinus : ℝ := 20.25

/-- Jucker allometric intercept -/
noncomputable def juckerAlpha : ℝ := 0.109

/-- Jucker allometric exponent -/
noncomputable def juckerBeta : ℝ := 1.79

/-- Snowdon bias correction factor -/
noncomputable def snowdonBias : ℝ := 1.02

/-! ## Budyko Constants -/

/-- Fu/Zhang omega parameter for Budyko curve -/
noncomputable def budykoOmega : ℝ := 2.63

/-! ## Basic positivity lemmas for constants -/

theorem solarConstant_pos : solarConstant > 0 := by norm_num [solarConstant]
theorem rhoWater_pos : rhoWater > 0 := by norm_num [rhoWater]
theorem cWater_pos : cWater > 0 := by norm_num [cWater]
theorem hBio_pos : hBio > 0 := by norm_num [hBio]
theorem nppMax_pos : nppMax > 0 := by norm_num [nppMax]
theorem hhvPinus_pos : hhvPinus > 0 := by norm_num [hhvPinus]
theorem lapseRate_pos : lapseRate > 0 := by norm_num [lapseRate]

end EEMTVerify.Constants
