/-
  Interval Arithmetic Infrastructure
  ===================================
  Provides types and lemmas for bounding computations,
  used to verify that intermediate values stay within physical ranges.
-/

import Mathlib.Order.Bounds.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

namespace EEMTVerify.Interval

/-! ## Physical Range Predicates

These predicates express that a value falls within a physically meaningful range.
They are used as preconditions in EEMT theorems. -/

/-- A value is a valid temperature in Celsius (DAYMET range). -/
def validTemp (T : ℝ) : Prop := -60 ≤ T ∧ T ≤ 60

/-- A value is a valid precipitation amount [mm]. -/
def validPrecip (P : ℝ) : Prop := 0 ≤ P ∧ P ≤ 500

/-- A value is a valid elevation [meters above sea level]. -/
def validElevation (z : ℝ) : Prop := -500 ≤ z ∧ z ≤ 9000

/-- A value is a valid solar radiation [W/m²]. -/
def validRadiation (I : ℝ) : Prop := 0 ≤ I ∧ I ≤ 1367

/-- A value is a valid Linke turbidity factor. -/
def validLinke (TL : ℝ) : Prop := 1.0 ≤ TL ∧ TL ≤ 8.0

/-- A value is a valid albedo. -/
def validAlbedo (α : ℝ) : Prop := 0 ≤ α ∧ α ≤ 1

/-- A value is a valid slope angle [radians]. -/
def validSlope (β : ℝ) : Prop := 0 ≤ β ∧ β ≤ Real.pi / 2

/-- A value is a valid EEMT output [MJ/m²/yr]. -/
def validEEMT (E : ℝ) : Prop := 0.1 ≤ E ∧ E ≤ 500

/-! ## Range lemmas -/

theorem validTemp_mean (Tmin Tmax : ℝ) (hmin : validTemp Tmin) (hmax : validTemp Tmax) :
    validTemp ((Tmin + Tmax) / 2) := by
  unfold validTemp at *
  constructor <;> linarith

theorem validAlbedo_nonneg {α : ℝ} (h : validAlbedo α) : 0 ≤ α := h.1
theorem validAlbedo_le_one {α : ℝ} (h : validAlbedo α) : α ≤ 1 := h.2

end EEMTVerify.Interval
