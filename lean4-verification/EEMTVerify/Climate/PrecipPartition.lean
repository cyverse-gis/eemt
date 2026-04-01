/-
  Precipitation Phase Partitioning Verification
  ==============================================
  Verifies the rain/snow partitioning formula used in:
  - Bash: eemt/eemt/reemt.sh (implicit in temperature-based logic)
  - Docs: docs/algorithms/climate-integration.md lines 265-288

  Key theorem: rain(T, P) + snow(T, P) = P for all T and P ≥ 0.
  This is a mass conservation law — no precipitation is created or destroyed.
-/

import Mathlib.Tactic

namespace EEMTVerify.Climate

/-! ## Precipitation Partitioning Model

Temperature thresholds:
- T ≥ 3.0°C: all rain
- T ≤ -1.0°C: all snow
- -1.0°C < T < 3.0°C: linear transition

The rain fraction in the transition zone is:
  f_rain = (T - T_snow) / (T_rain - T_snow) = (T + 1) / 4
-/

/-- Rain fraction as a function of temperature.
    Returns a value in [0, 1] representing the fraction of
    precipitation that falls as rain. -/
noncomputable def rainFraction (T : ℝ) : ℝ :=
  if T ≥ 3.0 then 1.0
  else if T ≤ -1.0 then 0.0
  else (T + 1.0) / 4.0

/-- Snow fraction as a function of temperature.
    Defined as 1 - rainFraction for mass conservation. -/
noncomputable def snowFraction (T : ℝ) : ℝ :=
  1.0 - rainFraction T

/-- Rain amount from total precipitation. -/
noncomputable def rain (T : ℝ) (P : ℝ) : ℝ :=
  rainFraction T * P

/-- Snow amount from total precipitation. -/
noncomputable def snow (T : ℝ) (P : ℝ) : ℝ :=
  snowFraction T * P

/-! ## Conservation Law -/

/-- **Mass Conservation**: Rain + Snow = Total Precipitation.
    This is the key theorem — no precipitation is created or destroyed
    by the phase partitioning. -/
theorem partition_conserves (T : ℝ) (P : ℝ) :
    rain T P + snow T P = P := by
  unfold rain snow snowFraction
  ring

/-- Rain fraction is between 0 and 1. -/
theorem rainFraction_bounded (T : ℝ) :
    0 ≤ rainFraction T ∧ rainFraction T ≤ 1 := by
  unfold rainFraction
  split_ifs with h1 h2
  · constructor <;> norm_num
  · constructor <;> norm_num
  · push_neg at h1 h2
    constructor
    · linarith
    · linarith

/-- Snow fraction is between 0 and 1. -/
theorem snowFraction_bounded (T : ℝ) :
    0 ≤ snowFraction T ∧ snowFraction T ≤ 1 := by
  unfold snowFraction
  obtain ⟨hlo, hhi⟩ := rainFraction_bounded T
  constructor <;> linarith

/-- Rain is non-negative when precipitation is non-negative. -/
theorem rain_nonneg (T : ℝ) (P : ℝ) (hP : P ≥ 0) : rain T P ≥ 0 := by
  unfold rain
  exact mul_nonneg (rainFraction_bounded T).1 hP

/-- Snow is non-negative when precipitation is non-negative. -/
theorem snow_nonneg (T : ℝ) (P : ℝ) (hP : P ≥ 0) : snow T P ≥ 0 := by
  unfold snow
  exact mul_nonneg (snowFraction_bounded T).1 hP

/-! ## Threshold Behavior -/

/-- Above 3°C, all precipitation is rain. -/
theorem all_rain_warm (T : ℝ) (P : ℝ) (hT : T ≥ 3.0) :
    rain T P = P ∧ snow T P = 0 := by
  unfold rain snow snowFraction rainFraction
  simp only [if_pos hT]
  constructor
  · ring
  · ring

/-- Below -1°C, all precipitation is snow. -/
theorem all_snow_cold (T : ℝ) (P : ℝ) (hT : T ≤ -1.0) :
    snow T P = P ∧ rain T P = 0 := by
  have hT3 : ¬(T ≥ 3.0) := by linarith
  unfold rain snow snowFraction rainFraction
  simp only [if_neg hT3, if_pos hT]
  constructor <;> ring

/-- In the transition zone, rain fraction increases linearly with temperature. -/
theorem transition_zone_linear (T₁ T₂ : ℝ)
    (h1lo : -1.0 < T₁) (h1hi : T₁ < 3.0)
    (_h2lo : -1.0 < T₂) (h2hi : T₂ < 3.0)
    (hlt : T₁ < T₂) :
    rainFraction T₁ < rainFraction T₂ := by
  have h1a : ¬(T₁ ≥ 3.0) := by linarith
  have h1b : ¬(T₁ ≤ -1.0) := by linarith
  have h2a : ¬(T₂ ≥ 3.0) := by linarith
  have h2b : ¬(T₂ ≤ -1.0) := by linarith
  unfold rainFraction
  simp only [if_neg h1a, if_neg h1b, if_neg h2a, if_neg h2b]
  linarith

/-- At 1°C (midpoint of transition), precipitation is split 50/50. -/
theorem midpoint_equal_split :
    rainFraction 1.0 = 0.5 := by
  unfold rainFraction
  simp [show ¬(1.0 : ℝ) ≥ 3.0 from by norm_num, show ¬(1.0 : ℝ) ≤ -1.0 from by norm_num]
  norm_num

/-! ## Structural Correspondence

The Lean definitions correspond to:

**Documentation** (`docs/algorithms/climate-integration.md` lines 265-288):
```
rain = P               if T ≥ 3.0°C
snow = P               if T ≤ -1.0°C
rain = P × (T+1)/4     if -1.0°C < T < 3.0°C
```

**Implementation note**: The `reemt.sh` script uses temperature thresholds
implicitly through `r.mapcalc` conditional expressions. The exact thresholds
(3.0°C for rain, -1.0°C for snow) match the documented values.
-/

end EEMTVerify.Climate
