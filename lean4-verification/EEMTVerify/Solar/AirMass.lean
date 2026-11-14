/-
  Optical Air Mass and Rayleigh Optical Thickness
  =================================================
  Verifies the atmospheric path length and scattering computations
  from the ESRA clear-sky radiation model.

  Source: rsun/rsun-core/src/radiation.rs `brad()` (lines computing air mass)
  Reference: Kasten & Young (1989) — optical air mass formula
  Docs: docs/algorithms/solar-radiation.md
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Solar

open Real EEMTVerify.Constants

/-! ## Atmospheric Refraction Correction

From rsun-core/src/radiation.rs brad():
```rust
let temp1 = 0.1594 + h0 * (1.123 + 0.065656 * h0);
let temp2 = 1.0 + h0 * (28.9344 + 277.3971 * h0);
let drefract = 0.061359 * temp1 / temp2;
let h0refract = h0 + drefract;
```
where h0 = solar altitude in radians.
-/

/-- Atmospheric refraction correction [radians].
    Adds a small positive angle to the apparent solar altitude
    to account for bending of light through the atmosphere. -/
noncomputable def refractionCorrection (solarAlt : ℝ) : ℝ :=
  let t1 := 0.1594 + solarAlt * (1.123 + 0.065656 * solarAlt)
  let t2 := 1.0 + solarAlt * (28.9344 + 277.3971 * solarAlt)
  0.061359 * t1 / t2

/-- Refraction-corrected solar altitude. -/
noncomputable def refractedAltitude (solarAlt : ℝ) : ℝ :=
  solarAlt + refractionCorrection solarAlt

/-! ## Elevation Pressure Correction

The barometric formula: atmospheric pressure decreases exponentially with altitude.
p/p₀ = exp(-z / H) where H = 8434.5 m is the scale height.
-/

/-- Elevation pressure correction factor.
    exp(-elevation / 8434.5), ranging from 1.0 at sea level to ~0.29 at Everest. -/
noncomputable def elevationCorrection (elevation : ℝ) : ℝ :=
  Real.exp (-elevation / scaleHeight)

/-- Elevation correction is strictly positive (exponential is always positive). -/
theorem elevationCorrection_pos (z : ℝ) : elevationCorrection z > 0 := by
  unfold elevationCorrection
  exact Real.exp_pos _

/-- Elevation correction is at most 1 (sea level maximum). -/
theorem elevationCorrection_le_one (z : ℝ) (hz : z ≥ 0) :
    elevationCorrection z ≤ 1 := by
  unfold elevationCorrection scaleHeight
  rw [Real.exp_le_one_iff]
  exact div_nonpos_of_nonpos_of_nonneg (neg_nonpos.mpr hz) (by norm_num)

/-- Elevation correction decreases with altitude (thinner atmosphere). -/
theorem elevationCorrection_antitone : Antitone elevationCorrection := by
  intro a b hab
  unfold elevationCorrection scaleHeight
  apply Real.exp_le_exp.mpr
  have hH : (8434.5 : ℝ) > 0 := by norm_num
  exact div_le_div_of_nonneg_right (neg_le_neg hab) (le_of_lt hH)

/-- At sea level, correction factor is 1. -/
theorem elevationCorrection_zero : elevationCorrection 0 = 1 := by
  unfold elevationCorrection scaleHeight
  simp

/-! ## Optical Air Mass (Kasten & Young 1989)

From rsun-core/src/radiation.rs:
```rust
let opt_air_mass = elev_corr / (sin_h0refract + 0.50572 *
    (h0refract.to_degrees() + 6.07995).powf(-1.6364));
```

The air mass represents the relative path length of sunlight through
the atmosphere compared to the zenith (overhead) path. At the horizon,
air mass ≈ 38; at zenith, air mass = 1.
-/

/-- Kasten-Young optical air mass formula.
    Accounts for atmospheric refraction and elevation. -/
noncomputable def opticalAirMass (solarAlt : ℝ) (elevation : ℝ) : ℝ :=
  let h0r := refractedAltitude solarAlt
  let sinH := Real.sin h0r
  let base := h0r * (180 / Real.pi) + 6.07995
  let denomTerm := 0.50572 * base.rpow (-1.6364)
  elevationCorrection elevation / (sinH + denomTerm)

/-! ## Rayleigh Optical Thickness

Two-branch polynomial approximation for the Rayleigh scattering coefficient.

From rsun-core/src/radiation.rs:
```rust
let rayl = if opt_air_mass <= 20.0 {
    1.0 / (6.6296 + opt_air_mass * (1.7513 + opt_air_mass *
        (-0.1202 + opt_air_mass * (0.0065 - 0.00013 * opt_air_mass))))
} else {
    1.0 / (10.4 + 0.718 * opt_air_mass)
};
```
-/

/-- Rayleigh optical thickness for air mass ≤ 20 (polynomial branch). -/
noncomputable def rayleighLow (m : ℝ) : ℝ :=
  1 / (6.6296 + m * (1.7513 + m * (-0.1202 + m * (0.0065 - 0.00013 * m))))

/-- Rayleigh optical thickness for air mass > 20 (linear branch). -/
noncomputable def rayleighHigh (m : ℝ) : ℝ :=
  1 / (10.4 + 0.718 * m)

/-- Rayleigh optical thickness (two-branch formula). -/
noncomputable def rayleighThickness (m : ℝ) : ℝ :=
  if m ≤ 20 then rayleighLow m else rayleighHigh m

/-! ## Rayleigh Thickness Properties -/

/-- Rayleigh thickness is positive for positive air mass.
    The denominator polynomial is positive for m ∈ [1, 20]. -/
theorem rayleighHigh_pos (m : ℝ) (hm : m > 0) : rayleighHigh m > 0 := by
  unfold rayleighHigh
  apply div_pos one_pos
  linarith

/-- High air mass branch: thickness decreases as air mass increases. -/
theorem rayleighHigh_antitone_on (a b : ℝ) (ha : a > 0) (_hb : b > 0) (hab : a ≤ b) :
    rayleighHigh b ≤ rayleighHigh a := by
  unfold rayleighHigh
  exact div_le_div_of_nonneg_left (by norm_num) (by linarith) (by linarith)

/-! ## Beam Transmittance

The beam transmittance through the atmosphere:
  τ_b = exp(-rayleigh × air_mass × 0.8662 × linke)

This is the Beer-Lambert law applied to atmospheric extinction.
-/

/-- Beam transmittance: fraction of direct radiation surviving atmospheric passage.
    τ_b = exp(-τ_rayleigh × m × 0.8662 × TL) -/
noncomputable def beamTransmittance (rayleigh : ℝ) (airMass : ℝ) (linke : ℝ) : ℝ :=
  Real.exp (-(rayleigh * airMass * (0.8662 * linke)))

/-- Beam transmittance is strictly positive (exponential property). -/
theorem beamTransmittance_pos (τ m TL : ℝ) : beamTransmittance τ m TL > 0 := by
  unfold beamTransmittance
  exact Real.exp_pos _

/-- Beam transmittance is at most 1 (can't amplify radiation).
    Holds when all parameters are non-negative. -/
theorem beamTransmittance_le_one (τ m TL : ℝ) (hτ : τ ≥ 0) (hm : m ≥ 0) (hTL : TL ≥ 0) :
    beamTransmittance τ m TL ≤ 1 := by
  unfold beamTransmittance
  rw [← Real.exp_zero]
  apply Real.exp_le_exp.mpr
  have h1 : τ * m ≥ 0 := mul_nonneg hτ hm
  have h2 : 0.8662 * TL ≥ 0 := by nlinarith
  linarith [mul_nonneg h1 h2]

/-- Higher Linke turbidity → lower transmittance (more atmospheric absorption). -/
theorem beamTransmittance_antitone_linke (τ m : ℝ) (hτ : τ ≥ 0) (hm : m ≥ 0) :
    Antitone (fun TL => beamTransmittance τ m TL) := by
  intro a b hab
  unfold beamTransmittance
  apply Real.exp_le_exp.mpr
  have h1 : τ * m ≥ 0 := mul_nonneg hτ hm
  have h2 : 0.8662 ≥ (0 : ℝ) := by norm_num
  nlinarith [mul_nonneg h1 h2]

/-! ## Structural Correspondence

These definitions decompose the `brad()` function from
rsun/rsun-core/src/radiation.rs (lines 21-69) into individually
verifiable components:

1. `refractionCorrection` → lines 27-30
2. `elevationCorrection` → line 33: `exp(-elevation / 8434.5)`
3. `opticalAirMass` → lines 35-36: Kasten-Young formula
4. `rayleighThickness` → lines 38-45: two-branch polynomial
5. `beamTransmittance` → line 49: Beer-Lambert law

The full `brad` computation chains these together:
  B_h = G_ext × sin(h) × τ_b
  B_tilt = B_h × s0 / sin(h)
-/

end EEMTVerify.Solar
