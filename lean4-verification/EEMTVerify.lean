/-
  EEMT Formal Verification Library
  ================================
  Lean 4 + Mathlib proofs for the Effective Energy and Mass Transfer
  geospatial modeling toolkit.

  This library formally verifies ~60 mathematical equations spanning:
  - Solar radiation (ESRA clear-sky model, GRASS GIS r.sun)
  - Climate integration (Magnus, PET, Budyko, precipitation)
  - Topographic analysis (TWI, slope, aspect, curvature)
  - EEMT core (NPP, E_BIO, E_PPT, energy balance)
  - Biomass energetics (allometric equations)
  - Thermodynamic foundation (exergy, Critical Zone energy)
-/

-- Foundation
import EEMTVerify.Foundation.Constants
import EEMTVerify.Foundation.Trigonometry
import EEMTVerify.Foundation.RealAnalysis
import EEMTVerify.Foundation.Interval

-- Solar Radiation
import EEMTVerify.Solar.Declination
import EEMTVerify.Solar.SolarConstant
import EEMTVerify.Solar.SunriseSunset
import EEMTVerify.Solar.SolarPosition
import EEMTVerify.Solar.CosIncidence
import EEMTVerify.Solar.AirMass
import EEMTVerify.Solar.BeamRadiation
import EEMTVerify.Solar.DiffuseRadiation
import EEMTVerify.Solar.TotalRadiation

-- Climate Integration
import EEMTVerify.Climate.PrecipPartition
import EEMTVerify.Climate.MagnusFormula
import EEMTVerify.Climate.LapseRate
import EEMTVerify.Climate.BudykoAET

-- Topographic Analysis
import EEMTVerify.Topographic.TWI
import EEMTVerify.Topographic.HornSlope

-- EEMT Core
import EEMTVerify.EEMT.NPPLieth
import EEMTVerify.EEMT.EBio
import EEMTVerify.EEMT.EPpt
import EEMTVerify.EEMT.EEMTCore
import EEMTVerify.EEMT.ProcessRates

-- Biomass & Energetics
import EEMTVerify.Biomass.Allometric
import EEMTVerify.Biomass.LandscapeEnergy

-- Cross-Implementation Consistency
import EEMTVerify.CrossImpl.RustWGSLConsistency

-- Global Properties
import EEMTVerify.Properties.ConservationLaws
