/-
  Real Analysis Helpers
  =====================
  Utilities for monotonicity, continuity, and exponential function
  properties used across EEMT equation proofs.
-/

import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Order.Monotone.Basic

namespace EEMTVerify.Analysis

open Real

/-! ## Exponential Function Properties -/

/-- exp is strictly positive everywhere. Convenience wrapper. -/
theorem exp_pos' (x : ℝ) : Real.exp x > 0 := Real.exp_pos x

/-- exp is strictly monotone increasing. -/
theorem exp_strictMono : StrictMono Real.exp := Real.exp_strictMono

/-- 1 + exp(x) > 1 for all x. Used in NPP Lieth model denominators. -/
theorem one_plus_exp_gt_one (x : ℝ) : 1 + Real.exp x > 1 := by
  linarith [Real.exp_pos x]

/-- 1 + exp(x) > 0 for all x. Ensures denominators are nonzero. -/
theorem one_plus_exp_pos (x : ℝ) : 1 + Real.exp x > 0 := by
  linarith [Real.exp_pos x]

/-- The logistic function 1/(1 + exp(-x)) is bounded in (0, 1). -/
theorem logistic_bounded (x : ℝ) :
    0 < 1 / (1 + Real.exp (-x)) ∧ 1 / (1 + Real.exp (-x)) < 1 := by
  constructor
  · positivity
  · rw [div_lt_one (one_plus_exp_pos (-x))]
    linarith [Real.exp_pos (-x)]

/-! ## Monotonicity Helpers -/

/-- If f is monotone increasing and g is monotone increasing, then f ∘ g is monotone. -/
theorem comp_monotone {f g : ℝ → ℝ} (hf : Monotone f) (hg : Monotone g) :
    Monotone (f ∘ g) :=
  hf.comp hg

/-- Scaling a monotone function by a positive constant preserves monotonicity. -/
theorem scale_monotone {f : ℝ → ℝ} (hf : Monotone f) {c : ℝ} (hc : 0 < c) :
    Monotone (fun x => c * f x) :=
  fun _ _ hab => mul_le_mul_of_nonneg_left (hf hab) (le_of_lt hc)

end EEMTVerify.Analysis
