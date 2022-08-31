(** Preprocessor

    The preprocessor turn mixed, raw literals (possibly simplified) into
    literals suitable for reasoning.
    Every literal undergoes preprocessing.
    Typically some clauses are also added to the solver on the side.
*)

open Sigs

type t
(** Preprocessor *)

val create : ?stat:Stat.t -> proof:proof_trace -> Term.store -> t

(** Actions given to preprocessor hooks *)
module type PREPROCESS_ACTS = sig
  val proof : proof_trace

  val mk_lit : ?sign:bool -> term -> lit
  (** [mk_lit t] creates a new literal for a boolean term [t]. *)

  val add_clause : lit list -> step_id -> unit
  (** pushes a new clause into the SAT solver. *)

  val add_lit : ?default_pol:bool -> lit -> unit
  (** Ensure the literal will be decided/handled by the SAT solver. *)
end

type preprocess_actions = (module PREPROCESS_ACTS)
(** Actions available to the preprocessor *)

type preprocess_hook = t -> preprocess_actions -> term -> term option
(** Given a term, preprocess it.

    The idea is to add literals and clauses to help define the meaning of
    the term, if needed. For example for boolean formulas, clauses
    for their Tseitin encoding can be added, with the formula acting
    as its own proxy symbol; or a new symbol might be added.

    @param preprocess_actions actions available during preprocessing.
*)

val on_preprocess : t -> preprocess_hook -> unit
(** Add a hook that will be called when terms are preprocessed *)

val preprocess_clause : t -> lit list -> step_id -> lit list * step_id
val preprocess_clause_array : t -> lit array -> step_id -> lit array * step_id

(** {2 Delayed actions} *)

(** Action that preprocess hooks took, but were not effected yet.
    The SMT solver itself should obtain these actions and perform them. *)
type delayed_action =
  | DA_add_clause of lit list * step_id
  | DA_add_lit of { default_pol: bool option; lit: lit }

val pop_delayed_actions : t -> delayed_action Iter.t
