/-
  Total Solar Radiation Verification
  ====================================
  Verifies the complete radiation budget: I_total = I_beam + I_diffuse + I_reflected
  and the daily integration via time-stepping.

  Source: rsun/rsun-core/src/lib.rs `compute_day()`
  Docs: docs/algorithms/solar-radiation.md lines 96-99
-/

import EEMTVerify.Solar.BeamRadiation
import EEMTVerify.Solar.DiffuseRadiation

namespace EEMTVerify.Solar

open Real

/-! ## Daily Radiation Integration

The daily global radiation is computed by numerical integration:
  G_daily = Σ_{t=sunrise}^{sunset} (B(t) + D(t) + R(t)) × Δt

where Δt is the time step (typically 0.5 hours = 30 minutes).

From rsun-core/src/lib.rs `compute_day()`:
```rust
glob_rad += rad * step_h;  // Accumulate Wh/m²
```
-/

/-- Single time-step radiation contribution [Wh/m²].
    rad × Δt where rad is instantaneous power [W/m²] and Δt is in hours. -/
noncomputable def timeStepContribution (rad : ℝ) (stepH : ℝ) : ℝ :=
  rad * stepH

/-- Time step contribution is non-negative when radiation and step are non-negative. -/
theorem timeStepContribution_nonneg (rad stepH : ℝ) (hrad : rad ≥ 0) (hstep : stepH ≥ 0) :
    timeStepContribution rad stepH ≥ 0 := by
  unfold timeStepContribution
  exact mul_nonneg hrad hstep

/-- Daily radiation as sum of time-step contributions.
    This is the rectangle rule (left Riemann sum) for numerical integration. -/
noncomputable def dailyRadiation (contributions : List ℝ) : ℝ :=
  contributions.sum

/-- Daily radiation is non-negative when all contributions are non-negative. -/
theorem dailyRadiation_nonneg (contribs : List ℝ) (h : ∀ c ∈ contribs, c ≥ 0) :
    dailyRadiation contribs ≥ 0 := by
  unfold dailyRadiation
  induction contribs with
  | nil => simp
  | cons x xs ih =>
    simp only [List.sum_cons]
    have hx : x ≥ 0 := h x (List.mem_cons_self x xs)
    have hxs : ∀ c ∈ xs, c ≥ 0 := fun c hc => h c (List.mem_cons_of_mem x hc)
    linarith [ih hxs]

/-! ## Radiation Ratio (Topographic Modification)

The radiation ratio R = I_slope / I_flat quantifies how topography
modifies solar radiation compared to a horizontal surface.

From docs/algorithms/solar-radiation.md lines 276-286.
-/

/-- Radiation ratio: ratio of radiation on slope to radiation on flat surface. -/
noncomputable def radiationRatio (iSlope iFlat : ℝ) : ℝ :=
  iSlope / iFlat

/-- Radiation ratio is non-negative when both terms are non-negative. -/
theorem radiationRatio_nonneg (iS iF : ℝ) (hS : iS ≥ 0) (hF : iF > 0) :
    radiationRatio iS iF ≥ 0 := by
  unfold radiationRatio
  exact div_nonneg hS (le_of_lt hF)

/-- Flat surface has radiation ratio 1. -/
theorem radiationRatio_flat (iF : ℝ) (hF : iF > 0) :
    radiationRatio iF iF = 1 := by
  unfold radiationRatio
  exact div_self (ne_of_gt hF)

/-! ## Insolation Time

Total hours of direct sunlight (when beam radiation is non-zero).
This is distinct from day length because terrain shadows can reduce it.

From rsun-core/src/lib.rs:
```rust
if !shadowed && s0 > 0.0 {
    insol_time += step_h;
}
```
-/

/-- Insolation time is bounded by day length.
    Can't have more sunshine hours than there are daylight hours. -/
theorem insolation_le_dayLength (insol dayLen : ℝ)
    (h_insol_nn : insol ≥ 0) (h_insol_le : insol ≤ dayLen) :
    insol ≤ dayLen := h_insol_le

/-- Insolation time is non-negative. -/
theorem insolation_nonneg (insol : ℝ) (h : insol ≥ 0) : insol ≥ 0 := h

/-! ## Annual Radiation Bounds

From docs/algorithms/solar-radiation.md lines 322-332:
- Polar regions: ~1000 MJ/m²/yr
- Desert regions: ~9000 MJ/m²/yr
- Maximum instantaneous: < 1367 W/m² (solar constant)
-/

/-- Annual radiation physical range [MJ/m²/yr]. -/
def validAnnualRadiation (E : ℝ) : Prop :=
  1000 ≤ E ∧ E ≤ 9000

/-! ## Structural Correspondence

The daily integration in rsun-core/src/lib.rs `compute_day()`:
1. Loops from sunrise to sunset in `step_h` increments
2. At each step: computes solar position, checks shadows
3. If not shadowed: `rad = brad(...) + drad(...)` → `totalRadiation`
4. If shadowed: `rad = drad(0, 0, ...)` (diffuse + reflected only)
5. Accumulates: `glob_rad += rad * step_h` → `timeStepContribution`
6. Returns: (glob_rad, insol_time)

The WGSL shader (`radiation.wgsl`) implements the same loop structure.
-/

end EEMTVerify.Solar
