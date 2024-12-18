import Egg.Tactic.Trace
import Lean

open Lean Meta Elab Tactic

-- TODO: Perform pruning during generation, not after.

-- TODO: It might be ok to silently prune non-autogenerated (that is, user-provided) rewrites with
--       unbound conditions, as certain conditional rewrites may only ever be intended to be used
--       with tc specialization, explosion, or other rewrite generation.

namespace Egg

def Rewrites.contains (tgts : Rewrites) (rw : Rewrite) : MetaM Bool := do
  let lhsAbs ← abstractMVars rw.lhs
  let rhsAbs ← abstractMVars rw.rhs
  let conds  ← rw.conds.mapM (AbstractMVarsResult.expr <$> abstractMVars ·.expr)
  tgts.anyM fun t => do
    unless lhsAbs.expr == (← abstractMVars t.lhs).expr do return false
    unless rhsAbs.expr == (← abstractMVars t.rhs).expr do return false
    let tConds ← t.conds.mapM (AbstractMVarsResult.expr <$> abstractMVars ·.expr)
    return conds == tConds

namespace Premises.GenM

private inductive RewriteCategory where
  | tagged
  | basic
  | builtins
  | derived

private def RewriteCategory.title : RewriteCategory → String
  | .tagged   => "Tagged"
  | .basic    => "Basic"
  | .builtins => "Builtin"
  | .derived  => "Derived"

private structure State where
  all       : Rewrites
  pruned    : Rewrites
  facts     : WithSyntax Facts
  tagged    : Rewrites
  basic     : Rewrites
  builtins  : Rewrites
  derived   : Rewrites

private instance : EmptyCollection State where
  emptyCollection := {
    all      := {}
    pruned   := {}
    facts    := {}
    tagged   := {}
    basic    := {}
    builtins := {}
    derived  := {}
  }

private def State.get (s : State) : RewriteCategory → Rewrites
  | .tagged   => s.tagged
  | .basic    => s.basic
  | .builtins => s.builtins
  | .derived  => s.derived

private def State.set (s : State) : RewriteCategory → Rewrites → State
  | .tagged,   rws => { s with tagged   := rws }
  | .basic,    rws => { s with basic    := rws }
  | .builtins, rws => { s with builtins := rws }
  | .derived,  rws => { s with derived  := rws }

abbrev _root_.Egg.Premises.GenM := StateT State TacticM

structure Result where
  all    : Rewrites
  pruned : Rewrites
  facts  : WithSyntax Facts

nonrec def run (m : GenM Unit) : TacticM Result := do
  let { all, pruned, facts, .. } ← Prod.snd <$> m.run ∅
  return { all, pruned, facts }

def all : GenM Rewrites :=
  return (← get).all

private def addAll (new : Rewrites) : GenM Unit := do
  modify fun s => { s with all := s.all ++ new }

def facts : GenM (WithSyntax Facts) :=
  return (← get).facts

private def addFacts (new : WithSyntax Facts) : GenM Unit := do
  modify fun s => { s with facts := s.facts ++ new }

private def addPruned (new : Rewrites) : GenM Unit := do
  modify fun s => { s with pruned := s.pruned ++ new }

def set (cat : RewriteCategory) (rws : Rewrites) : GenM Unit :=
  modify (·.set cat rws)

nonrec def get (cat : RewriteCategory) : GenM Rewrites :=
  return (← get).get cat

private def prune (rws : Rewrites) (stx? : Option (Array Syntax) := none) :
    GenM (Rewrites × Array Syntax) := do
  let mut keep : Rewrites := #[]
  let mut keepStx := #[]
  let mut pruned := #[]
  for rw in rws, idx in [:rws.size] do
    if ← keep.contains rw <||> (← all).contains rw then
      pruned := pruned.push rw
    else
      keep := keep.push rw
      if let some stx := stx? then keepStx := keepStx.push stx[idx]!
  addPruned pruned
  return (keep, keepStx)

def generate' (cat : RewriteCategory) (cfg : Config.Erasure) (g : GenM Premises) : GenM Unit := do
  let { rws := ⟨new, stxs⟩, facts } ← g
  addFacts facts
  let mut (new, stx) ← prune new (if stxs.isEmpty then none else stxs)
  let cls := `egg.rewrites
  if let .derived := cat then
    let inv ← catchInvalidConditionals new (throw := false)
    new := new.filter fun n => !inv.any (n.src == ·.src)
    addPruned inv
    withTraceNode cls (fun _ => return m!"{cat.title} ({new.size})") do (Rewrites.trace new) #[] cfg cls
  else
    withTraceNode cls (fun _ => return m!"{cat.title} ({new.size})") do new.trace stx cfg cls
    _ ← catchInvalidConditionals new (throw := true)
  set cat new
  addAll new
where
  catchInvalidConditionals (rws : Rewrites) (throw : Bool) : MetaM Rewrites := do
    let mut remove := #[]
    let mut nextRw := false
    for rw in rws do
      nextRw := false
      for cond in rw.conds do
        if nextRw then break
        for m in cond.mvars.visibleExpr cfg do
          unless (rw.mvars.lhs.visibleExpr cfg).contains m ||  (rw.mvars.rhs.visibleExpr cfg).contains m do
            if throw
            then throwError m!"egg: rewrite {rw.src} contains an unbound condition (expression)"
            else remove := remove.push rw; nextRw := true; break
        if nextRw then break
        for m in cond.mvars.visibleLevel cfg do
          unless (rw.mvars.lhs.visibleLevel cfg).contains m || (rw.mvars.rhs.visibleLevel cfg).contains m do
            if throw
            then throwError m!"egg: rewrite {rw.src} contains an unbound condition (level)"
            else remove := remove.push rw; nextRw := true; break
    return remove

def generate (cat : RewriteCategory) (cfg : Config.Erasure) (g : GenM Rewrites) : GenM Unit := do
  generate' cat cfg do return { rws.elems := ← g, rws.stxs := #[], facts := ⟨#[], #[]⟩ }
