
module type S = Solver_intf.S
(** Safe external interface of solvers. *)

module Make_pure_sat(Th: Solver_intf.PLUGIN_SAT)
  : S with type formula = Th.formula
       and module Formula = Th.Formula
       and type proof = Th.proof
       and module Proof = Th.Proof
       and type theory = unit

module Make_cdcl_t(Th : Solver_intf.PLUGIN_CDCL_T)
  : S with type formula = Th.formula
       and module Formula = Th.Formula
       and type proof = Th.proof
       and module Proof = Th.Proof
       and type theory = Th.t
