/-
  Global Conservation Laws and Cross-Cutting Properties
  ======================================================
  Collects conservation laws, physical constraints, and properties
  that span multiple EEMT equation domains.
-/

import EEMTVerify.Climate.PrecipPartition
import EEMTVerify.Solar.DiffuseRadiation
import EEMTVerify.EEMT.EEMTCore
import EEMTVerify.EEMT.ProcessRates

namespace EEMTVerify.Properties

open EEMTVerify.Climate EEMTVerify.Solar EEMTVerify.EEMT EEMTVerify.Constants

/-! ## Conservation Laws

These are the fundamental physical constraints that any correct
implementation must satisfy. Violation indicates a bug.
-/

/-- **Precipitation Mass Conservation**: rain + snow = total precipitation.
    No water is created or destroyed by phase partitioning. -/
theorem precip_mass_conservation (T P : ℝ) :
    rain T P + snow T P = P :=
  partition_conserves T P

/-- **View Factor Conservation**: sky view + terrain view = 1.
    The full hemisphere is partitioned between sky and terrain. -/
theorem view_factor_conservation (slope : ℝ) :
    skyViewFactor slope + terrainViewFactor slope = 1 :=
  view_factors_sum_one slope

/-- **Radiation Decomposition**: total = beam + diffuse + reflected.
    Energy is conserved in the three-component radiation model. -/
theorem radiation_decomposition (B D R : ℝ) :
    totalRadiation B D R = B + D + R :=
  totalRadiation_decomposition B D R

/-- **EEMT Energy Decomposition**: EEMT = E_BIO + E_PPT.
    Total pedogenic energy is the sum of biological and precipitation components. -/
theorem eemt_energy_decomposition (npp pEff T : ℝ) :
    eemt npp pEff T = eBio npp + ePpt pEff T :=
  eemt_decomposition npp pEff T

/-- **Regime Exhaustiveness**: every EEMT value is either water-limited or energy-limited. -/
theorem eemt_regime_exhaustive (E : ℝ) :
    isWaterLimited E ∨ isEnergyLimited E :=
  regime_partition E

/-- **Regime Exclusivity**: no EEMT value is both water-limited and energy-limited. -/
theorem eemt_regime_exclusive (E : ℝ) :
    ¬(isWaterLimited E ∧ isEnergyLimited E) :=
  regime_exclusive E

/-! ## Non-Negativity Invariants

All physical quantities (radiation, energy, biomass) must be non-negative.
-/

/-- Rain is non-negative. -/
theorem rain_nonneg' (T P : ℝ) (hP : P ≥ 0) : rain T P ≥ 0 :=
  rain_nonneg T P hP

/-- Snow is non-negative. -/
theorem snow_nonneg' (T P : ℝ) (hP : P ≥ 0) : snow T P ≥ 0 :=
  snow_nonneg T P hP

/-- EEMT is non-negative under physical constraints. -/
theorem eemt_nonneg' (npp pEff T : ℝ) (hNPP : npp ≥ 0) (hP : pEff ≥ 0) :
    eemt npp pEff T ≥ 0 :=
  eemt_nonneg npp pEff T hNPP hP

/-- Reflected radiation is non-negative. -/
theorem reflected_nonneg' (α Gh slope : ℝ) (hα : α ≥ 0) (hGh : Gh ≥ 0) :
    reflectedRadiation α Gh slope ≥ 0 :=
  reflectedRadiation_nonneg α Gh slope hα hGh

/-- Total radiation is non-negative when components are non-negative. -/
theorem total_radiation_nonneg' (B D R : ℝ) (hB : B ≥ 0) (hD : D ≥ 0) (hR : R ≥ 0) :
    totalRadiation B D R ≥ 0 :=
  totalRadiation_nonneg B D R hB hD hR

/-! ## Monotonicity Relationships

Expected physical monotonic relationships between variables.
-/

/-- Warmer temperatures → more NPP (temperature-limited Lieth model). -/
theorem warmer_more_npp : StrictMono nppTemp :=
  nppTemp_strictMono

/-- More vegetation → more biological energy. -/
theorem more_npp_more_ebio : StrictMono eBio :=
  eBio_strictMono

/-- Higher EEMT → more chemical weathering. -/
theorem more_eemt_more_weathering : StrictMono chemDenudation :=
  chemDenudation_strictMono

/-- Higher EEMT → less soil production (exponential decay). -/
theorem more_eemt_less_soil_production : Antitone soilProductionRate :=
  soilProduction_antitone

/-! ## Physical Bounds

Upper and lower limits from documented ranges.
-/

/-- NPP is bounded above by 3000 g/m²/yr (Lieth model limit). -/
theorem npp_upper_bound (T : ℝ) : nppTemp T < nppMax :=
  nppTemp_lt_max T

/-- Soil production rate is bounded above by 0.05 mm/yr. -/
theorem soil_production_upper (E : ℝ) (hE : E ≥ 0) : soilProductionRate E ≤ 0.05 :=
  soilProduction_le_max E hE

/-- Biomass accumulation is bounded by carrying capacity (50 kg/m²). -/
theorem biomass_carrying_capacity (E : ℝ) : biomassAccum E < 50 :=
  biomassAccum_lt_carrying E

/-- Biomass at regime threshold is exactly half carrying capacity. -/
theorem biomass_at_threshold : biomassAccum 70 = 25 :=
  biomassAccum_at_threshold

/-! ## Zero Conditions

Conditions under which quantities are exactly zero.
-/

/-- E_PPT is zero when temperature is at or below freezing. -/
theorem eppt_zero_frozen (pEff T : ℝ) (hT : T ≤ 0) : ePpt pEff T = 0 :=
  ePpt_zero_frozen pEff T hT

/-- EEMT reduces to E_BIO in cold climates. -/
theorem eemt_cold (npp pEff T : ℝ) (hT : T ≤ 0) : eemt npp pEff T = eBio npp :=
  bio_dominates_cold npp pEff T hT

/-- Reflected radiation is zero on flat surfaces. -/
theorem reflected_zero_flat (α Gh : ℝ) : reflectedRadiation α Gh 0 = 0 :=
  reflectedRadiation_flat α Gh

end EEMTVerify.Properties
