(** Core proofs for SMT and congruence closure. *)

open Sidekick_core_logic

type lit = Lit.t

val lemma_cc : lit Iter.t -> Proof_term.t
(** [lemma_cc proof lits] asserts that [lits] form a tautology for the theory
       of uninterpreted functions. *)

val define_term : Term.t -> Term.t -> Proof_term.t
(** [define_term cst u proof] defines the new constant [cst] as being equal
       to [u].
       The result is a proof of the clause [cst = u] *)

val proof_p1 : Proof_term.step_id -> Proof_term.step_id -> Proof_term.t
(** [proof_p1 p1 p2], where [p1] proves the unit clause [t=u] (t:bool)
       and [p2] proves [C \/ t], is the Proof_term.t that produces [C \/ u],
       i.e unit paramodulation. *)

val proof_r1 : Proof_term.step_id -> Proof_term.step_id -> Proof_term.t
(** [proof_r1 p1 p2], where [p1] proves the unit clause [|- t] (t:bool)
       and [p2] proves [C \/ ¬t], is the Proof_term.t that produces [C \/ u],
       i.e unit resolution. *)

val proof_res :
  pivot:Term.t -> Proof_term.step_id -> Proof_term.step_id -> Proof_term.t
(** [proof_res ~pivot p1 p2], where [p1] proves the clause [|- C \/ l]
       and [p2] proves [D \/ ¬l], where [l] is either [pivot] or [¬pivot],
       is the Proof_term.t that produces [C \/ D], i.e boolean resolution. *)

val with_defs : Proof_term.step_id -> Proof_term.step_id Iter.t -> Proof_term.t
(** [with_defs pr defs] specifies that [pr] is valid only in
       a context where the definitions [defs] are present. *)

val lemma_true : Term.t -> Proof_term.t
(** [lemma_true (true) p] asserts the clause [(true)] *)

val lemma_preprocess :
  Term.t -> Term.t -> using:Proof_term.step_id Iter.t -> Proof_term.t
(** [lemma_preprocess t u ~using p] asserts that [t = u] is a tautology
       and that [t] has been preprocessed into [u].

       The theorem [/\_{eqn in using} eqn |- t=u] is proved using congruence
       closure, and then resolved against the clauses [using] to obtain
       a unit equality.

       From now on, [t] and [u] will be used interchangeably.
       @return a Proof_term.t ID for the clause [(t=u)]. *)

val lemma_rw_clause :
  Proof_term.step_id ->
  res:lit Iter.t ->
  using:Proof_term.step_id Iter.t ->
  Proof_term.t
(** [lemma_rw_clause prc ~res ~using], where [prc] is the proof of [|- c],
       uses the equations [|- p_i = q_i] from [using]
       to rewrite some literals of [c] into [res]. This is used to preprocess
       literals of a clause (using {!lemma_preprocess} individually). *)
