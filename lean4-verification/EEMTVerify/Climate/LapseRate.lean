/-
  Temperature Lapse Rate Verification
  =====================================
  Verifies the elevation-based temperature correction.

  Source: eemt/eemt/reemt.sh (r.mapcalc expressions)
  Docs: docs/algorithms/climate-integration.md lines 173-180
-/

import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Climate

open EEMTVerify.Constants

/-! ## Environmental Lapse Rate

The standard environmental lapse rate: temperature decreases by
approximately 6.49°C per 1000m of elevation gain.

From eemt/eemt/reemt.sh:
```bash
r.mapcalc "tmin_loc = tmin - 0.00649 * (dem_10m - dem_1km)"
r.mapcalc "tmax_loc = tmax - 0.00649 * (dem_10m - dem_1km)"
```
-/

/-- Temperature at a given elevation, adjusted from a reference elevation.
    T(z) = T_ref - γ × (z - z_ref)
    where γ = 0.00649 °C/m (6.49 °C/km) -/
noncomputable def lapseAdjust (tRef : ℝ) (zRef : ℝ) (z : ℝ) : ℝ :=
  tRef - lapseRate * (z - zRef)

/-- Lapse rate identity: at the reference elevation, temperature is unchanged. -/
theorem lapseAdjust_at_ref (tRef zRef : ℝ) :
    lapseAdjust tRef zRef zRef = tRef := by
  unfold lapseAdjust
  ring

/-- **Temperature decreases with elevation** (the fundamental lapse rate property). -/
theorem lapseAdjust_antitone (tRef zRef : ℝ) :
    Antitone (fun z => lapseAdjust tRef zRef z) := by
  intro a b hab
  unfold lapseAdjust lapseRate
  linarith

/-- Higher elevation → lower temperature (explicit version). -/
theorem lapseAdjust_decreasing (tRef zRef z₁ z₂ : ℝ) (hz : z₁ < z₂) :
    lapseAdjust tRef zRef z₂ < lapseAdjust tRef zRef z₁ := by
  unfold lapseAdjust lapseRate
  linarith

/-- Temperature difference between two elevations is linear. -/
theorem lapseAdjust_diff (tRef zRef z₁ z₂ : ℝ) :
    lapseAdjust tRef zRef z₁ - lapseAdjust tRef zRef z₂ = lapseRate * (z₂ - z₁) := by
  unfold lapseAdjust
  ring

/-- Per 1000m of elevation gain, temperature drops by 6.49°C. -/
theorem lapse_per_km (tRef zRef z : ℝ) :
    lapseAdjust tRef zRef z - lapseAdjust tRef zRef (z + 1000) = lapseRate * 1000 := by
  unfold lapseAdjust
  ring

/-! ## Mean Temperature

T_mean = (T_min + T_max) / 2

From docs/algorithms/climate-integration.md lines 131-132.
-/

/-- Mean temperature from daily min and max. -/
noncomputable def meanTemp (tMin tMax : ℝ) : ℝ := (tMin + tMax) / 2

/-- Mean temperature is between min and max. -/
theorem meanTemp_bounded (tMin tMax : ℝ) (h : tMin ≤ tMax) :
    tMin ≤ meanTemp tMin tMax ∧ meanTemp tMin tMax ≤ tMax := by
  unfold meanTemp
  constructor <;> linarith

/-- Mean of lapse-adjusted temperatures equals lapse-adjusted mean. -/
theorem lapse_mean_commute (tMin tMax zRef z : ℝ) :
    meanTemp (lapseAdjust tMin zRef z) (lapseAdjust tMax zRef z) =
    lapseAdjust (meanTemp tMin tMax) zRef z := by
  unfold meanTemp lapseAdjust
  ring

/-! ## Structural Correspondence

Lean `lapseAdjust` matches reemt.sh:
```bash
r.mapcalc "tmin_loc = tmin - 0.00649 * (dem_10m - dem_1km)"
```
Where `tmin` = T_ref, `dem_1km` = z_ref, `dem_10m` = z.

The coefficient 0.00649 matches `lapseRate` exactly.
-/

end EEMTVerify.Climate
