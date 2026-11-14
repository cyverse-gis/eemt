/-
  Diffuse and Reflected Radiation Verification
  ==============================================
  Verifies the drad() function computing diffuse sky radiation
  and ground-reflected radiation on tilted surfaces.

  Source: rsun/rsun-core/src/radiation.rs `drad()`
  Origin: GRASS GIS r.sun rsunlib.c drad()
  Model: ESRA clear-sky (Suri & Hofierka)
  Docs: docs/algorithms/solar-radiation.md lines 71-93
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Solar

open Real EEMTVerify.Constants

/-! ## Sky View Factor

The fraction of the sky hemisphere visible from a tilted surface.
F_sky = (1 + cos(slope)) / 2

On flat ground: F_sky = 1 (full hemisphere visible)
On vertical surface: F_sky = 0.5
-/

/-- Sky view factor for a tilted surface.
    F_sky = (1 + cos(slope)) / 2 -/
noncomputable def skyViewFactor (slope : ℝ) : ℝ :=
  (1 + Real.cos slope) / 2

/-- Terrain view factor (complement of sky view).
    F_terrain = (1 - cos(slope)) / 2 -/
noncomputable def terrainViewFactor (slope : ℝ) : ℝ :=
  (1 - Real.cos slope) / 2

/-- Sky and terrain view factors sum to 1. -/
theorem view_factors_sum_one (slope : ℝ) :
    skyViewFactor slope + terrainViewFactor slope = 1 := by
  unfold skyViewFactor terrainViewFactor
  ring

/-- Sky view factor is in [0, 1]. -/
theorem skyViewFactor_bounded (slope : ℝ) :
    0 ≤ skyViewFactor slope ∧ skyViewFactor slope ≤ 1 := by
  unfold skyViewFactor
  constructor
  · linarith [Real.neg_one_le_cos slope]
  · linarith [Real.cos_le_one slope]

/-- Terrain view factor is in [0, 1]. -/
theorem terrainViewFactor_bounded (slope : ℝ) :
    0 ≤ terrainViewFactor slope ∧ terrainViewFactor slope ≤ 1 := by
  unfold terrainViewFactor
  constructor
  · linarith [Real.cos_le_one slope]
  · linarith [Real.neg_one_le_cos slope]

/-- Flat surface: sky view factor is 1 (full sky visible). -/
theorem skyViewFactor_flat : skyViewFactor 0 = 1 := by
  unfold skyViewFactor
  simp [Real.cos_zero]

/-- Flat surface: terrain view factor is 0 (no terrain visible). -/
theorem terrainViewFactor_flat : terrainViewFactor 0 = 0 := by
  unfold terrainViewFactor
  simp [Real.cos_zero]

/-! ## Reflected Radiation

The ground-reflected component:
  R = albedo × G_h × F_terrain
  = albedo × (B_h + D_h) × (1 - cos(slope)) / 2

From rsun-core/src/radiation.rs drad():
```rust
let ground_refl = albedo * glob_h * (1.0 - slope.cos()) / 2.0;
```
-/

/-- Reflected radiation from surrounding terrain [W/m²].
    R = albedo × global_horizontal × terrain_view_factor -/
noncomputable def reflectedRadiation (albedo : ℝ) (globalHoriz : ℝ) (slope : ℝ) : ℝ :=
  albedo * globalHoriz * terrainViewFactor slope

/-- **Reflected radiation is non-negative** when inputs are non-negative. -/
theorem reflectedRadiation_nonneg (α Gh slope : ℝ)
    (hα : α ≥ 0) (hGh : Gh ≥ 0) :
    reflectedRadiation α Gh slope ≥ 0 := by
  unfold reflectedRadiation
  apply mul_nonneg
  · exact mul_nonneg hα hGh
  · exact (terrainViewFactor_bounded slope).1

/-- **Reflected radiation is zero on flat surfaces** (no terrain to reflect). -/
theorem reflectedRadiation_flat (α Gh : ℝ) :
    reflectedRadiation α Gh 0 = 0 := by
  unfold reflectedRadiation
  rw [terrainViewFactor_flat]
  ring

/-- Higher albedo → more reflected radiation (monotonic). -/
theorem reflectedRadiation_monotone_albedo (Gh slope : ℝ) (hGh : Gh ≥ 0) :
    Monotone (fun α => reflectedRadiation α Gh slope) := by
  intro a b hab
  unfold reflectedRadiation
  apply mul_le_mul_of_nonneg_right
  · exact mul_le_mul_of_nonneg_right hab hGh
  · exact (terrainViewFactor_bounded slope).1

/-- Reflected radiation bounded by albedo × G_h (since F_terrain ≤ 1). -/
theorem reflectedRadiation_le (α Gh slope : ℝ)
    (hα : α ≥ 0) (hGh : Gh ≥ 0) :
    reflectedRadiation α Gh slope ≤ α * Gh := by
  unfold reflectedRadiation
  calc α * Gh * terrainViewFactor slope
      ≤ α * Gh * 1 := by
        apply mul_le_mul_of_nonneg_left (terrainViewFactor_bounded slope).2 (mul_nonneg hα hGh)
    _ = α * Gh := by ring

/-! ## Diffuse Radiation (ESRA Model)

The ESRA diffuse model computes horizontal diffuse irradiance as:
  D_h = G_ext × (a₁ + a₂×sin(h) + a₃×sin²(h)) × Tₙ

where a₁, a₂, a₃, Tₙ are polynomial functions of the Linke turbidity factor.
The full tilted-surface correction involves sky-view geometry and
anisotropy corrections that are complex but bounded.

We verify the structural decomposition and key properties rather than
the full polynomial coefficients.
-/

/-- ESRA diffuse transmission function (simplified structure).
    Represents the fraction of extraterrestrial radiation that
    reaches the surface as diffuse light. -/
noncomputable def diffuseTransmission (solarAlt : ℝ) (linke : ℝ) : ℝ :=
  let tn := -0.015843 + linke * (0.030543 + 0.0003797 * linke)
  let a1b := 0.26463 + linke * (-0.061581 + 0.0031408 * linke)
  let a1 := max (0.0022 / tn) a1b
  let a2 := 2.04020 + linke * (0.018945 - 0.011161 * linke)
  let a3 := -1.3025 + linke * (0.039231 + 0.0085079 * linke)
  (a1 + a2 * Real.sin solarAlt + a3 * (Real.sin solarAlt) ^ 2) * tn

/-- Total radiation decomposition: the three-component model.
    I_total = I_beam + I_diffuse + I_reflected -/
noncomputable def totalRadiation (beam diffuse reflected : ℝ) : ℝ :=
  beam + diffuse + reflected

/-- **Total radiation decomposition is exact** (by definition). -/
theorem totalRadiation_decomposition (B D R : ℝ) :
    totalRadiation B D R = B + D + R := by
  unfold totalRadiation; ring

/-- **Total radiation is non-negative** when all components are non-negative. -/
theorem totalRadiation_nonneg (B D R : ℝ) (hB : B ≥ 0) (hD : D ≥ 0) (hR : R ≥ 0) :
    totalRadiation B D R ≥ 0 := by
  unfold totalRadiation; linarith

/-! ## Structural Correspondence

The Lean model corresponds to rsun-core/src/radiation.rs `drad()`:

| Component | Rust code location | Lean definition |
|-----------|-------------------|-----------------|
| Sky view factor | `r_sky = (1 + cos(slope)) / 2` | `skyViewFactor` |
| Terrain view factor | `(1 - cos(slope)) / 2` | `terrainViewFactor` |
| Reflected radiation | `albedo * glob_h * (1-cos(slope))/2` | `reflectedRadiation` |
| Diffuse transmission | ESRA polynomial coefficients | `diffuseTransmission` |
| Global horizontal | `B_h + D_h` | used in reflected calculation |

**Known cross-implementation difference**:
WGSL shader (`radiation.wgsl`) hardcodes `cbh = cdh = 1.0` (clear sky only).
Rust version accepts arbitrary `cbh`/`cdh` parameters for real-sky corrections.
-/

end EEMTVerify.Solar
