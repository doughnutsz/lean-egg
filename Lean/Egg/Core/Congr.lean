import Egg.Core.Normalize
import Lean
open Lean Meta

namespace Egg.Congr

inductive Rel where
  | eq
  | iff
  deriving Inhabited

structure _root_.Egg.Congr where
  rel : Congr.Rel
  lhs : Expr
  rhs : Expr
  deriving Inhabited

def Rel.relate (e₁ e₂ : Expr) : Rel → MetaM Expr
  | eq  => mkEq e₁ e₂
  | iff => return mkIff e₁ e₂

def Rel.mkRefl (expr : Expr) : Rel → MetaM Expr
  | eq  => mkEqRefl expr
  | iff => mkAppM ``Iff.refl #[expr]

def Rel.mkSymm (proof : Expr) : Rel → MetaM Expr
  | eq  => mkEqSymm proof
  | iff => mkAppM ``Iff.symm #[proof]

  def Rel.mkTrans (proof₁ proof₂ : Expr) : Rel → MetaM Expr
  | eq  => mkEqTrans proof₁ proof₂
  | iff => mkAppM ``Iff.trans #[proof₁, proof₂]

def Rel.mkMP (proof : Expr) : Rel → MetaM Expr
  | eq  => mkAppM ``Eq.mp #[proof]
  | iff => mkAppM ``Iff.mp #[proof]

def Rel.mkMPR (proof : Expr) : Rel → MetaM Expr
  | eq  => mkAppM ``Eq.mpr #[proof]
  | iff => mkAppM ``Iff.mpr #[proof]

def expr (cgr : Congr) : MetaM Expr := do
  match cgr.rel with
  | .eq  => mkEq cgr.lhs cgr.rhs
  | .iff => return mkIff cgr.lhs cgr.rhs

-- Since `=` and `↔` are not heterogeneous, we assume `lhs` and `rhs` to have the same type.
def type (cgr : Congr) : MetaM Expr :=
  inferType cgr.lhs

def from? (type : Expr) : MetaM (Option Congr) := do
  let type ← normalize type .noReduce
  if let some (_, lhs, rhs) := type.eq? then
    return some { rel := .eq, lhs, rhs }
  else if let some (lhs, rhs) := type.iff? then
    return some { rel := .iff, lhs, rhs }
  else
    return none

def from! (type : Expr) : MetaM Congr := do
  return (← Congr.from? type).get!
