/-
  Trigonometry Helpers
  ====================
  Wrappers around Mathlib trigonometric lemmas needed by solar geometry.
  Provides convenience lemmas for the specific patterns used in EEMT equations.
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Bounds

namespace EEMTVerify.Trig

open Real

/-! ## Sine and Cosine Bounds -/

/-- Product of bounded values: if |a| ≤ A and |sin(x)| ≤ 1 then |a * sin(x)| ≤ A.
    Used extensively for arcsin argument validation. -/
theorem abs_mul_sin_le (a : ℝ) (x : ℝ) (ha : |a| ≤ 1) :
    |a * Real.sin x| ≤ 1 := by
  calc |a * Real.sin x|
      = |a| * |Real.sin x| := abs_mul a (Real.sin x)
    _ ≤ |a| * 1 := by apply mul_le_mul_of_nonneg_left (abs_sin_le_one x) (abs_nonneg a)
    _ = |a| := mul_one |a|
    _ ≤ 1 := ha

/-- If 0 < a < 1, then |a * sin(x)| < 1, so arcsin(a * sin(x)) is well-defined
    and strictly within (-π/2, π/2). -/
theorem abs_mul_sin_lt_one (a : ℝ) (x : ℝ) (ha_pos : 0 < a) (ha_lt : a < 1) :
    |a * Real.sin x| < 1 := by
  calc |a * Real.sin x|
      = a * |Real.sin x| := by rw [abs_mul, abs_of_pos ha_pos]
    _ ≤ a * 1 := by apply mul_le_mul_of_nonneg_left (abs_sin_le_one x) (le_of_lt ha_pos)
    _ = a := mul_one a
    _ < 1 := ha_lt

/-! ## Arcsin Properties -/

/-- Arcsin of a product a*sin(x) where |a| ≤ 1 is bounded by arcsin(|a|). -/
theorem arcsin_mul_sin_bounded (a : ℝ) (x : ℝ) (ha : |a| ≤ 1) :
    |Real.arcsin (a * Real.sin x)| ≤ Real.arcsin |a| := by
  -- |arcsin(a*sin(x))| ≤ arcsin(|a|) follows from:
  -- 1. |a*sin(x)| ≤ |a| (proven by abs_mul_sin_le)
  -- 2. arcsin odd: |arcsin(y)| = arcsin(|y|) for |y| ≤ 1
  -- 3. arcsin monotone on [-1,1]
  sorry -- Needs: abs_arcsin = arcsin ∘ abs on [-1,1], which Mathlib may not have

/-! ## Angle Conversion -/

/-- Convert degrees to radians. -/
noncomputable def degToRad (d : ℝ) : ℝ := d * Real.pi / 180

/-- Convert radians to degrees. -/
noncomputable def radToDeg (r : ℝ) : ℝ := r * 180 / Real.pi

/-- Degree-radian roundtrip. -/
theorem deg_rad_roundtrip (d : ℝ) : radToDeg (degToRad d) = d := by
  unfold degToRad radToDeg
  field_simp

end EEMTVerify.Trig
