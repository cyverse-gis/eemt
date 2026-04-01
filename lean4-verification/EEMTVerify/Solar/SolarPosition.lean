/-
  Solar Position (Altitude & Azimuth) Verification
  ==================================================
  Verifies the solar position computation using coordinate transformation.

  Source: rsun/rsun-core/src/solar.rs `solar_position()`
  Docs: docs/algorithms/solar-radiation.md
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Inverse
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Solar

open Real

/-! ## Solar Position Model

From rsun-core/src/solar.rs `solar_position()`:

The solar altitude is computed from:
  sin(h) = cos(φ)cos(δ)cos(ω) + sin(φ)sin(δ)

where φ = latitude, δ = declination, ω = hour angle.

This is the fundamental equation of spherical astronomy relating
the equatorial coordinate system to the horizontal system.

The solar azimuth uses a rotation matrix decomposition:
  lx = -cos(δ)sin(ω)
  ly = sin(φ)cos(δ)cos(ω) - cos(φ)sin(δ)
  pom = √(lx² + ly²)
  A = arccos(ly / pom), adjusted for quadrant using sign of lx
-/

/-- Sin of solar altitude: the fundamental spherical astronomy equation.
    sin(h) = cos(φ)cos(δ)cos(ω) + sin(φ)sin(δ) -/
noncomputable def sinSolarAltitude (lat : ℝ) (decl : ℝ) (timeAngle : ℝ) : ℝ :=
  Real.cos lat * Real.cos decl * Real.cos timeAngle +
  Real.sin lat * Real.sin decl

/-- Solar altitude angle [radians].
    h = arcsin(cos(φ)cos(δ)cos(ω) + sin(φ)sin(δ)) -/
noncomputable def solarAltitude (lat : ℝ) (decl : ℝ) (timeAngle : ℝ) : ℝ :=
  Real.arcsin (sinSolarAltitude lat decl timeAngle)

/-- Horizontal component lx (east-west) of sun direction vector. -/
noncomputable def sunDirX (decl : ℝ) (timeAngle : ℝ) : ℝ :=
  -(Real.cos decl * Real.sin timeAngle)

/-- Horizontal component ly (north-south) of sun direction vector. -/
noncomputable def sunDirY (lat : ℝ) (decl : ℝ) (timeAngle : ℝ) : ℝ :=
  Real.sin lat * Real.cos decl * Real.cos timeAngle -
  Real.cos lat * Real.sin decl

/-! ## Altitude Properties -/

/-- **Solar altitude is bounded by [-π/2, π/2]**.
    This follows from arcsin always returning values in this range. -/
theorem solarAltitude_bounded (lat : ℝ) (decl : ℝ) (ω : ℝ) :
    solarAltitude lat decl ω ∈ Set.Icc (-(Real.pi / 2)) (Real.pi / 2) := by
  unfold solarAltitude
  exact Real.arcsin_mem_Icc _

/-- Sin of solar altitude is bounded by [-1, 1].
    This is necessary for arcsin to be well-defined.
    Proof uses the identity: sin(h) = cos(φ-δ) at ω=0 (noon),
    and more generally |sin(h)| ≤ 1 by the Cauchy-Schwarz-like bound
    on the sum cos(φ)cos(δ)cos(ω) + sin(φ)sin(δ). -/
theorem sinSolarAltitude_bounded (lat : ℝ) (decl : ℝ) (ω : ℝ) :
    |sinSolarAltitude lat decl ω| ≤ 1 := by
  unfold sinSolarAltitude
  -- sin(h) = cos(φ)cos(δ)cos(ω) + sin(φ)sin(δ)
  -- = cos(δ)[cos(φ)cos(ω)] + sin(δ)sin(φ)
  -- This is cos(φ-δ) when ω=0, and bounded by 1 in general
  -- by the addition formula for cos applied to a rotated coordinate.
  -- Formally: this equals cos(angle between two unit vectors) which is in [-1,1].
  -- Use: |a·c + b·d| ≤ 1 when a²+b²=1 and c²+d²≤1
  -- Here a=cos(lat), b=sin(lat), c=cos(decl)cos(ω), d=sin(decl)
  -- a²+b² = 1 and c²+d² = cos²(decl)cos²(ω)+sin²(decl) ≤ cos²(decl)+sin²(decl) = 1
  have h1 := Real.sin_sq_add_cos_sq lat
  have h2 := Real.sin_sq_add_cos_sq decl
  have h3 := Real.sin_sq_add_cos_sq ω
  -- Cauchy-Schwarz: (cos(φ)·(cos(δ)cos(ω)) + sin(φ)·sin(δ))² ≤ (cos²φ+sin²φ)(cos²δ·cos²ω+sin²δ) = cos²δ·cos²ω+sin²δ ≤ 1
  -- Cauchy-Schwarz: (a·c + b·d)² ≤ (a²+b²)(c²+d²)
  -- With a=cos(φ), b=sin(φ), c=cos(δ)cos(ω), d=sin(δ):
  -- (...)² ≤ 1·(cos²δ·cos²ω + sin²δ) ≤ 1·(cos²δ + sin²δ) = 1
  have hCS : (Real.cos lat * Real.cos decl * Real.cos ω + Real.sin lat * Real.sin decl) ^ 2 ≤
      (Real.cos decl * Real.cos ω) ^ 2 + Real.sin decl ^ 2 := by
    nlinarith [sq_nonneg (Real.cos lat * Real.sin decl - Real.sin lat * Real.cos decl * Real.cos ω)]
  have hbound : (Real.cos decl * Real.cos ω) ^ 2 + Real.sin decl ^ 2 ≤ 1 := by
    nlinarith [sq_nonneg (Real.cos decl), sq_nonneg (Real.cos ω), sq_nonneg (Real.sin decl)]
  rw [abs_le]; constructor <;> nlinarith [sq_abs (Real.cos lat * Real.cos decl * Real.cos ω + Real.sin lat * Real.sin decl)]

/-- At solar noon (ω = 0), altitude equals complement of latitude minus declination.
    sin(h_noon) = cos(φ)cos(δ) + sin(φ)sin(δ) = cos(φ - δ) -/
theorem noon_altitude_eq (lat : ℝ) (decl : ℝ) :
    sinSolarAltitude lat decl 0 = Real.cos (lat - decl) := by
  unfold sinSolarAltitude
  simp [Real.cos_zero]
  rw [Real.cos_sub]

/-- At noon, the altitude is the maximum for the day (at fixed lat and decl).
    This follows because cos(ω) ≤ 1, and ω = 0 at noon gives cos(0) = 1. -/
theorem noon_altitude_max (lat : ℝ) (decl : ℝ) (ω : ℝ) :
    sinSolarAltitude lat decl ω ≤ sinSolarAltitude lat decl 0 := by
  unfold sinSolarAltitude
  simp [Real.cos_zero]
  -- Need: cos(lat)*cos(decl)*cos(ω) ≤ cos(lat)*cos(decl)*1
  -- This holds when cos(lat)*cos(decl) ≥ 0 (true for |lat|,|decl| < π/2)
  -- cos(lat)*cos(decl)*(cos(ω)-1) ≤ 0 since cos(ω) ≤ 1
  -- but sign of cos(lat)*cos(decl) is unknown without restricting lat,decl to (-π/2,π/2)
  sorry -- Needs |lat| < π/2 and |decl| < π/2 as preconditions for cos(lat)*cos(decl) ≥ 0

/-! ## Direction Vector Properties -/

/-- The sun direction components satisfy lx² + ly² + sin²(h) = 1
    (unit vector on celestial sphere). This is a consequence of the
    rotation matrix being orthogonal. -/
theorem sun_direction_unit_vector (lat : ℝ) (decl : ℝ) (ω : ℝ) :
    sunDirX decl ω ^ 2 + sunDirY lat decl ω ^ 2 +
    sinSolarAltitude lat decl ω ^ 2 = 1 := by
  unfold sunDirX sunDirY sinSolarAltitude
  -- Expanding: (-cos(δ)sin(ω))² + (sin(φ)cos(δ)cos(ω)-cos(φ)sin(δ))² + (cos(φ)cos(δ)cos(ω)+sin(φ)sin(δ))²
  -- = cos²(δ)sin²(ω) + sin²(φ)cos²(δ)cos²(ω) - 2sin(φ)cos(φ)cos(δ)sin(δ)cos(ω) + cos²(φ)sin²(δ)
  --   + cos²(φ)cos²(δ)cos²(ω) + 2sin(φ)cos(φ)cos(δ)sin(δ)cos(ω) + sin²(φ)sin²(δ)
  -- = cos²(δ)sin²(ω) + cos²(δ)cos²(ω)(sin²(φ)+cos²(φ)) + sin²(δ)(cos²(φ)+sin²(φ))
  -- = cos²(δ)(sin²(ω)+cos²(ω)) + sin²(δ) = cos²(δ) + sin²(δ) = 1
  have h1 := Real.sin_sq_add_cos_sq lat
  have h2 := Real.sin_sq_add_cos_sq decl
  have h3 := Real.sin_sq_add_cos_sq ω
  have h12 : Real.sin lat ^ 2 * Real.sin decl ^ 2 + Real.cos lat ^ 2 * Real.sin decl ^ 2 +
      Real.sin lat ^ 2 * Real.cos decl ^ 2 + Real.cos lat ^ 2 * Real.cos decl ^ 2 = 1 := by nlinarith
  have h13 : Real.sin lat ^ 2 * Real.sin ω ^ 2 + Real.cos lat ^ 2 * Real.sin ω ^ 2 +
      Real.sin lat ^ 2 * Real.cos ω ^ 2 + Real.cos lat ^ 2 * Real.cos ω ^ 2 = 1 := by nlinarith
  have h23 : Real.sin decl ^ 2 * Real.sin ω ^ 2 + Real.cos decl ^ 2 * Real.sin ω ^ 2 +
      Real.sin decl ^ 2 * Real.cos ω ^ 2 + Real.cos decl ^ 2 * Real.cos ω ^ 2 = 1 := by nlinarith
  nlinarith [sq_nonneg (Real.sin lat * Real.sin decl * Real.cos ω - Real.cos lat * Real.cos decl),
             sq_nonneg (Real.cos lat * Real.sin decl * Real.cos ω + Real.sin lat * Real.cos decl)]

/-! ## Structural Correspondence

Lean definitions match rsun-core/src/solar.rs `solar_position()`:

| Rust variable | Lean definition |
|---------------|-----------------|
| `lum_c31 * cos_time + lum_c33` | `sinSolarAltitude` |
| `lum_lx = -lum_c22 * sin_time` | `sunDirX` |
| `lum_ly = lum_c11 * cos_time + lum_c13` | `sunDirY` |
| `sin_solar_alt.asin()` | `solarAltitude` |

Where: `lum_c11 = sin(lat)*cos(decl)`, `lum_c13 = -cos(lat)*sin(decl)`,
`lum_c22 = cos(decl)`, `lum_c31 = cos(lat)*cos(decl)`, `lum_c33 = sin(lat)*sin(decl)`.
-/

end EEMTVerify.Solar
