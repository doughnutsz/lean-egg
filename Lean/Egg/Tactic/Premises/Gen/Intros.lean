import Egg.Tactic.Premises.Gen.GenM
import Lean

open Lean Meta Elab Tactic

namespace Egg

def genIntros (fvars : Array FVarId) (cfg : Config) (amb : MVars.Ambient) : TacticM Rewrites := do
  let mut rws := #[]
  for fvar in fvars, idx in [:fvars.size] do
    let proof := .fvar fvar
    let type   ← fvar.getType
    let src   := .intro idx
    let rwCfg := { cfg with amb }
    if let some rw ← Rewrite.from? proof type src rwCfg then
      rws := rws.push rw
    if cfg.genGroundEqs then
      if let some eq ← Rewrite.mkGroundEq? proof type (.ground src) rwCfg then
        rws := rws.push eq
  return rws
