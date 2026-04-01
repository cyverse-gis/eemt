import Lake
open Lake DSL

package EEMTVerify where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib EEMTVerify where
  srcDir := "."
  roots := #[`EEMTVerify]

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.16.0"
